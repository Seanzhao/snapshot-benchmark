require "cfoundry"
require "json"
require "vcap/logging"
require "fileutils"
require "restclient"
require "uri"

module Utils
  FileUtils.mkdir_p("log")
  logfile = "log/testlog.log."+ DateTime.parse(Time.now.to_s).strftime('%Y%m%d_%H%M').to_s
  loglevel = :debug
  config = {:level => loglevel, :file => logfile}
  VCAP::Logging.setup_from_config(config)
  $log = VCAP::Logging.logger(File.basename($0))  

  def login(target, email, password)
    $log.info "login target: #{target}, email: #{email}, password: #{password}"
    begin
      client = CFoundry::Client.new(target)
      $log.info client.inspect 
      token = client.login(:username => email, :password => password)
      $log.debug "client: #{client.inspect}, token: #{token.inspect}"
      [token, client]
    rescue Exception => e
      $log.error("Fail to login target: #{target}, email: #{email}, password: #{password}\n#{e.inspect}") 
    end
  end
    
  def cleanup(client)
    $log.debug("Cleanup all applicatioins and services")
    if client.nil? == true
      return
    end
    if client.service_instances.nil? != true
      client.service_instances.each{ |s| s.delete! }
    end
    if client.apps.nil? != true
      client.apps.each { |app| app.delete! }
    end
  end

  def push_app(manifest, client)
    $log.info("push app: #{manifest.inspect}")
    path = File.join(File.dirname(__FILE__), "../app")
    path = File.absolute_path(path)
    app = client.apps.first
    if app
      sync_app(app, path)
    else
      app = create_app(manifest, path, client)
    end
    app
  end
  
  def create_app(manifest, path, client)
    app = client.app
    app.name = manifest["name"]
    app.space = client.current_space if client.current_space
    app.total_instances = manifest["instances"] ? manifest["instances"] : 1
    all_frameworks = client.frameworks
    all_runtimes = client.runtimes
    framework = all_frameworks.select { |f| f.name == manifest["framework"]}.first
    runtime = all_runtimes.select { |f| f.name == manifest["runtime"]}.first
    app.framework = framework
    app.runtime = runtime

    target_base = client.target.split(".", 2).last
    url = "#{manifest["name"]}-#{manifest["plan"]}.#{target_base}"
    app.urls = [url]
    app.memory = manifest["memory"]
    begin
      $log.info("create application: #{app.inspect}")
      app.create!
    rescue Exception => e 
      $log.error("fail to create application #{app.name}\n #{e.inspect}")
    end 
    
    begin
      upload_app(app, path)
    rescue Exception => e
      $log.error("Fail to upload application source: #{app.name}, file path: #{path}\n#{e.inspect}")
    end
    start(app)
    if manifest["services"]
      manifest["services"].each do |service|
        instance = create_service(manifest, service["service"], client)
	bind_service(instance, app)
      end
    end
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
  
  def create_service(manifest, service_name, client)
    services = client.services
    services.reject! {|s| s.label != manifest["service"]}
    service = services.first
    $log.debug "service instance: #{service}"
    instance = client.service_instance
    instance.name = service_name

    instance.type = service.type
    instance.vendor = service.label
    instance.version = service.version
    instance.tier = manifest["plan"]
    begin
      $log.info "create service instance: #{instance.inspect}, (#{instance.vendor}, #{instance.version}, #{instance.tier})"
      instance.create!
    rescue Exception => e
      $log.error "Fail to create service instance: #{instance.inspect}  #{e.inspect}"
    end
    instance;
  end
  
  def bind_service(instance, app)
    begin
      $log.info("Binding service: #{instance.name} to application: #{app.name}")
      unless app.binds?(instance)
        app.bind(instance)
      end
    rescue Exception => e
      $log.error("fail to bind service: #{instance.name} to application: #{app.name}\n#{e.inspect}")
    end
  end
  
  def sync_app(app, path)
    upload_app(app, path)
    restart(app)
  end

  def stop(app)
    begin
      $log.info("stop application: #{app.name}")
      app.stop! unless app.stopped?
    rescue Exception => e
      $log.error("fail to stop application #{app.name}\n#{e.inspect}")
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

  def restart(app)
    stop(app)
    start(app)
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

  def create_db(uri, service_name)
    path = URI.encode_www_form("service" => service_name)
    url = "#{uri}/createdb?#{path}"
    begin
      $log.info("Create db. service: #{service_name}; url: #{url}")
      response = RestClient.post(url,"", {})
      $log.debug("response: #{response.code}, body: #{response.body}")
    rescue Exception => e                                      
      $log.error("fail to create datastore. url: #{url}, service: #{service_name}\n#{e.inspect}")
    end
  end

  def preload_data(uri, service_name)
    path=URI.encode_www_form({"service" => service_name})
    url = "#{uri}/insertdata?#{path}"
    begin
      $log.info("Load data: service #{service_name}, PUT url: #{url}")
      response = RestClient.put(url, "", {})
      $log.debug("response: #{response.code}, body: #{response.body}")
    rescue Exception => e
      $log.error("fail to load data. url: #{url}, \n#{e.inspect}")
    end
  end
end
