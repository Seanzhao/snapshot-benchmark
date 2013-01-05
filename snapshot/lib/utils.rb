require "cfoundry"
require "json"
require "vcap/logging"
require "fileutils"
require "results"

module Utils
  include Results
  FileUtils.mkdir_p("log")
  logfile = "log/testlog.log."+ DateTime.parse(Time.now.to_s).strftime('%Y%m%d_%H%M').to_s
  loglevel = :debug
  config = {:level => loglevel, :file => logfile}
  VCAP::Logging.setup_from_config(config)
  $log = VCAP::Logging.logger(File.basename($0))

  def login(target, email, password)
    puts "login target: #{target}, email: #{email}, password: #{password}"
    begin
      client = CFoundry::Client.new(target)
      $log.info("login target: #{target}, email: #{email}, password: #{password}")
      token = client.login({:username => email, :password => password})
      $log.debug("client: #{client.inspect}")
      [token, client]
    rescue Exception => e
      $log.error("Fail to login target: #{target}, email: #{email}, password: #{password}\n#{e.inspect}")
    end 
  end

  def push_app(manifest, client, suffix)
    puts "push application, #{manifest}"
    $log.info("push application, #{manifest}")
    app = client.apps.first
    path = File.join(File.dirname(__FILE__), "../app")
    path = File.absolute_path(path)
    #if app 
    #  cleanup(client)
    #end
    app = create_app(manifest, path, client, suffix)
    app
  end

  def create_app(manifest, path, client, suffix)
    app = client.app
    app.name = "#{manifest["name"]}-#{suffix}"
    app.space = client.current_space if client.current_space
    app.total_instances = manifest["instances"] ? manifest["instances"] : 1

    all_frameworks = client.frameworks
    all_runtimes = client.runtimes
    framework = all_frameworks.select {|f| f.name == manifest["framework"]}.first
    runtime = all_runtimes.select {|f| f.name == manifest["runtime"]}.first

    app.framework = framework
    app.runtime = runtime
    
    target_base = client.target.split(".", 2).last
    url = "#{manifest["name"]}-#{suffix}.#{target_base}"
    app.urls = [url] if url

    app.memory = manifest["memory"]
    begin
      $log.debug("create application #{app.name}")
      app.create!
    rescue Exception => e
      $log.error("fail to create application #{app.name}\n#{e.inspect}")
    end

    begin
      upload_app(app, path)
    rescue Exception => e
      $log.error("fail to upload application source. application: #{app.name}, file path: #{path}\n#{e.inspect}")
    end

    start(app)
    app
  end

  def upload_app(app, path)
    begin
      $log.debug("upload application source, name: #{app.name}, path: #{path}")
      app.upload(path)
    rescue Exception => e
      $log.error("fail to upload application source, name: #{app.name}, path: #{path}\n#{e.inspect}")
    end 
  end   

  def cleanup(client)
    $log.debug("cleanup all applications")
    if client.apps.nil? == false
      client.apps.each do |app| 
        $log.debug "app name #{app.name}"
        if app.name =~ /snapshot-mega/
	  app.delete!
          $log.debug("delete app: #{app.inspect}")
	end
      end
    end
  end

  def start(app)
    begin
      $log.info("start application: #{app.name}")
      app.start! unless app.started?
    rescue
      $log.error("fail to start application #{app.name}")
    end
    
    check_application(app)
  end

  APP_CHECK_LIMIT = 60
  def check_application(app)
    seconds = 0
    until app.healthy?
      sleep 1
      seconds += 1
      if seconds == APP_CHECK_LIMIT
        $log.error("application #{app.name} cannot be started in #{APP_CHECK_LIMIT} seconds")
      end
    end
  end

  def wait_job(uri, header, token, service, job_id)
    return {} unless job_id
    #timeout = 10 * 60 * 60
    timeout = 10 * 60
    sleep_time = 10
    while timeout > 0
      sleep sleep_time 
      timeout -= sleep_time
    
      path = URI.encode_www_form({"token"   => token,
                                  "service"     => service,
                                  "jobid"       => job_id})
      url = "#{uri}/snapshot/queryjobstatus?#{path}"
      begin
        $log.debug("query job status. url: #{url}")
        resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
        response = resource.get(header)
	job = JSON.parse(response.body)
        $log.debug("query job status. Job: #{job}")
        return job if job["status"] == "completed" || job["status"] == "failed"
      rescue Exception => e
        $log.error("fail to query job status. url: #{url}\n#{e.inspect}")
      end
    end
  end
  def take_snapshot(uri, token, service, header)
    result = "pass"
    path = URI.encode_www_form({"token"   => token,
                                "service" => service})
    url = "#{uri}/snapshot/create?#{path}"
    begin
      puts "create snapshot. url: #{url}"
      $log.info("create snapshot. url: #{url}")
      resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
      response = resource.post("", header)
            
      $log.debug("response: #{response.code}, body: #{response.body}")
      job = JSON.parse(response.body)
      job = wait_job(uri,header, token, service,job["job_id"])
      if job.is_a?(Hash) && job["status"] && job["status"] == "completed"
        result = "pass"
      else
        result = "fail"
      end 
    rescue Exception => e
      $log.error("fail to create snapshot. url: #{url}\n#{e.inspect}")
      result = "fail"
    end 
    duration = job_duration(job["start_time"], job["complete_time"])
    insert_result("Take Snapshot", result, duration)
    response
  end 

  def list_snapshot(uri, token, service, header, snapshot_id = nil)
    result = "pass"
    path = URI.encode_www_form({"token"   => token,
                                "service"     => service,
                                "snapshotid"  => snapshot_id})
    url = "#{uri}/snapshot/list?#{path}"
    begin
      puts "list snapshot. url: #{url}"
      $log.info("list snapshot. url: #{url}, service: #{service}," +
                    " snapshot_id: #{snapshot_id.inspect}")
      #timeout = 5 * 60 * 60 # wait 30 mins
      timeout = 30 * 60
      sleep_time = 1
      while timeout > 0
        sleep(sleep_time)
        timeout -= sleep_time

        resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
        response = resource.post("", header)
        $log.debug("response: #{response.code}, body: #{response.body}")
        break if response.code == 200 #&& has_snapshot?(response.body)
      end
    rescue Exception => e
      $log.error("fail to list snapshot. url: #{url}, "+
                     "service: #{service}, snapshot_id: #{snapshot_id.inspect}\n#{e.inspect}")
      result = "fail"
    end
    insert_result("List Snapshot", result, 0)
    result == "pass" ? response.body : {"snapshots" => []}.to_json
  end

  def has_snapshot?(json_body)
    snapshots = JSON.parse(json_body)
    !snapshots["snapshots"].empty?
  end

  def delete_snapshot(uri, token, service, header, snapshot_id)
    result = "pass"
    path = URI.encode_www_form({"token"   => token,
                                "service"     => service,
                                "snapshotid"  => snapshot_id})
    url = "#{uri}/snapshot/delete?#{path}"
    begin
      puts "delete snapshot. url: #{url}"
      $log.info("delete snapshot. url: #{url}, service: #{service}," +
                    " snapshot_id: #{snapshot_id.inspect}")
      resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
      response = resource.post("", header)
      $log.debug("response: #{response.code}, body: #{response.body}")
      job = JSON.parse(response.body)
      job = wait_job(uri,header,token,service,job["job_id"])
      if job.is_a?(Hash) && job["result"] && job["result"]["result"] == "ok"
        result = "pass"
      else
        result = "fail"
      end
    rescue Exception => e
      $log.error("fail to delete snapshot. url: #{url}, "+
                     "service: #{service}, snapshot_id: #{snapshot_id.inspect}\n#{e.inspect}")
      result = "fail"
    end
    duration = job_duration(job["start_time"], job["complete_time"])
    insert_result( "Delete Snapshot", result, duration)
  end
  
  def rollback_snapshot(uri, token, service, header, snapshot_id)
    result = "pass"
    path = URI.encode_www_form({"token"   => token,
                                "service"     => service,
                                "snapshotid"  => snapshot_id})
    url = "#{uri}/snapshot/rollback?#{path}"
    begin
      puts "rollback snapshot. url: #{url}"
      $log.info("rollback snapshot. url: #{url}, service: #{service}," +
                    " snapshot_id: #{snapshot_id.inspect}")
      resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
      response = resource.post("", header)
      job = JSON.parse(response.body)
      job = wait_job(uri,header,token,service,job["job_id"])
      if !(job.is_a?(Hash) && job["result"] && job["result"]["result"] && job["result"]["result"] == "ok")
        result = "fail"
      end

      $log.debug("response: #{response.code}, body: #{response.body}")
    rescue Exception => e
      $log.error("fail to rollback snapshot. url: #{url}, "+
                     "service: #{service}, snapshot_id: #{snapshot_id.inspect}\n#{e.inspect}")
      result = "fail"
    end
    duration = job_duration(job["start_time"], job["complete_time"])
    insert_result("Rollback Snapshot", result, duration)
  end

  def import_from_data(uri, token, service, header, snapshot_id)
    result = "pass"
    path = URI.encode_www_form({"token"   => token,
                                "service"     => service,
                                "snapshotid"  => snapshot_id})
    url = "#{uri}/snapshot/createurl?#{path}"
    begin
      puts "create url. url: #{url}"
      $log.info("create url. url: #{url}, service: #{service}," +
                    " snapshot_id: #{snapshot_id.inspect}")
      resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
      response = resource.post("", header)
      $log.debug("response: #{response.code}, body: #{response.body}")
      job = JSON.parse(response.body)
      job = wait_job(uri,header,token,service,job["job_id"])
      if !(job.is_a?(Hash) && job["result"] && job["result"]["url"])
        result = "fail"
        #duration = job_duration(job["start_time"], job["complete_time"])
        #insert_result("create serialized URL", result, duration)
        return
      end
      serialized_url = job["result"]["url"]


      path = URI.encode_www_form({"token"   => token,
                                  "service"     => service,
                                  "snapshotid"  => snapshot_id})
      url = "#{uri}/snapshot/importdata?#{path}"
      body = {"url" => serialized_url}.to_json

      puts "import from data. url: #{url}"
      $log.info("import from data. url: #{url}, service: #{service}," +
                    " snapshot_id: #{snapshot_id.inspect}, body: #{body}")
      resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
      response = resource.post(body, header)
      $log.debug("response: #{response.code}, body: #{response.body}")
      job = JSON.parse(response.body)
      job = wait_job(uri,header,token,service,job["job_id"])
      if !(job.is_a?(Hash) && job["result"] && job["result"]["snapshot_id"])
        result = "fail"
      end
    rescue Exception => e
      $log.error("fail to import from data. url: #{url}, "+
                     "service: #{service}, snapshot_id: #{snapshot_id.inspect}\n#{e.inspect}")
      result = "fail"
    end
    duration = job_duration(job["start_time"], job["complete_time"])
    insert_result("Export/Import from Data", result, duration)
    result
  end

  def import_from_url(uri, token, service, header, snapshot_id)
    result = "pass"
    path = URI.encode_www_form({"token"   => token,
                                "service"     => service,
                                "snapshotid"  => snapshot_id})
    url = "#{uri}/snapshot/createurl?#{path}"
    #url = "#{uri}/snapshot/importurl?#{path}"
    begin
      puts "create url. url: #{url}"
      $log.info("create url. url: #{url}, service: #{service}," +
                    " snapshot_id: #{snapshot_id.inspect}")
      resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
      response = resource.post("", header)
      $log.debug("response: #{response.code}, body: #{response.body}")
      job = JSON.parse(response.body)
      job = wait_job(uri,header,token,service,job["job_id"])
      if !(job.is_a?(Hash) && job["result"] && job["result"]["url"])
        result = "fail"
        duration = job_duration(job["start_time"], job["complete_time"])
        #insert_result("create serialized URL", result, duration)
        return
      end
      serialized_url = job["result"]["url"]

      path = URI.encode_www_form({"token"   => token,
                                  "service"     => service})
      url = "#{uri}/snapshot/importurl?#{path}"
      body = {"url" => job["result"]["url"]}.to_json

      puts "import from url. url: #{url}, body: #{body}"
      $log.info("import from url. url: #{url}, service: #{service}, body: #{body}")
      resource = RestClient::Resource.new url, :timeout => 90000, :open_timeout => 90000
      response = resource.post(body, header)
      $log.debug("response: #{response.code}, body: #{response.body}")
      job = JSON.parse(response.body)
      job = wait_job(uri,header,token,service,job["job_id"])
      if !(job.is_a?(Hash) && job["result"] && job["result"]["snapshot_id"])
        result = "fail"
      end
    rescue Exception => e
      $log.error("fail to import from url. url: #{url}, "+
                     "service: #{service}, snapshot_id: #{snapshot_id.inspect}\n#{e.inspect}")
      result = "fail"
    end
    duration = job_duration(job["start_time"], job["complete_time"])
    insert_result("Import from URL", result, duration)
    [result, serialized_url]
  end

  def random_snapshot(json_body)
    snapshots = JSON.parse(json_body)
    rand = Random.new(Time.now.usec)
    list = snapshots["snapshots"]
    index = rand(list.size)
    snapshot_id = list[index]["snapshot_id"]
    $log.debug("random select snapshot. snapshot id: #{snapshot_id}")
    snapshot_id
  end

  def snapshot_ids(json_body)
    ids = []
    snapshots = JSON.parse(json_body)
    list = snapshots["snapshots"]
    list.each do |snapshot|
      ids << snapshot["snapshot_id"]
    end
    ids
  end

  def job_duration(start, complete)
    time = /\d{2}:\d{2}:\d{2}/
    startstr = time.match(start)
    completestr = time.match(complete)
    #puts startstr, completestr
    startarr = startstr[0].split(":")
    completearr = completestr[0].split(":")
    duration = (completearr[0].to_i - startarr[0].to_i) * 3600 +
    (completearr[1].to_i - startarr[1].to_i) * 60 + 
    (completearr[2].to_i - startarr[2].to_i)
    duration > 0 ? duration : 0
  end
end

