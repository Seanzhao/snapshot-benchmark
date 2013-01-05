require "logger"
require "cfoundry"
require "yaml"

$:.unshift(File.join(File.dirname(__FILE__), "lib"))
require "utils"
require "results"

PAUSE_TIME = 5;
APP_CONFIG = File.join(File.dirname(__FILE__), "config/app.yml")
app_config = YAML.load_file(APP_CONFIG)
SERVICE_CONFIG = File.join(File.dirname(__FILE__), "config/service_config.yml")
service_config = YAML.load_file(SERVICE_CONFIG)
USER_CONFIG = File.join(File.dirname(__FILE__), "config/user.yml")
user_config = YAML.load_file(USER_CONFIG)
BOSH_CONFIG = "/home/seanzhao/deployments/dev173/dev173.yml"
bosh_config = YAML.load_file(BOSH_CONFIG)

target = service_config["target"]

include Results
include Utils

now = Time.now
create_results()
usertoken, userclient = login(target, user_config["email"], user_config["password"])
cleanup(userclient)

apps = []
uris = []
threads = []
service_config["services"].each do |service|
  service["plans"].each do |plan|
    app = push_app(app_config["application"], userclient, "#{service["name"]}-#{plan["name"]}")
    puts "Pushing application: #{app_config["application"]["name"]}-#{service["name"]}-#{plan["name"]}"
    apps << app
    uri = app.urls.first
    uris << uri
    header = {
              "target" => "http://#{target}",
              "app"    => app.name}
    plan["users"].each do |user|
      puts "User credential: #{user["email"]}, #{user["password"]}"
      quota = bosh_config["properties"]["service_plans"][service["name"]][plan["name"].to_s]["configuration"]["lifecycle"]["snapshot"]["quota"]
      puts "quota: #{quota.inspect}"
      # user level thread
      # threads << Thread.new do
	puts "User credential: #{user["email"]}, #{user["password"]}"
        token, client = login(target, user["email"], user["password"])
	user["services"].each do |servicename|
	# service instance level thread
        threads << Thread.new do

	  #cleanup previously created snapshots
	  sleep(rand * PAUSE_TIME)
	  snapshots = list_snapshot(uri, token, servicename["service"], header)
          if(has_snapshot?(snapshots))
	    ids = snapshot_ids(snapshots)
	    ids.each do |id|
	      delete_snapshot(uri, token, servicename["service"], header, id)
	      sleep(rand * PAUSE_TIME)
	    end
	  end
          
	  quota.times do
	    take_snapshot(uri, token, servicename["service"], header)
	    sleep(rand * PAUSE_TIME)
	  end

	  snapshots = list_snapshot(uri, token, servicename["service"], header)
	  sleep(rand * PAUSE_TIME)

          if (has_snapshot?(snapshots) && (rand(100) <= 20))
	    snapshot_id = random_snapshot(snapshots)
	    rollback_snapshot(uri, token, servicename["service"], header, snapshot_id)
	    sleep(rand * PAUSE_TIME)

            if (has_snapshot?(snapshots) && (rand(100) <= 50))
	      snapshot_id = random_snapshot(snapshots)
	      delete_snapshot(uri, token, servicename["service"], header, snapshot_id)
	      sleep(rand * PAUSE_TIME)
              
	      if(rand(100) >= 50)
	        snapshots = list_snapshot(uri, token, servicename["service"], header)
                if has_snapshot?(snapshots) 
                  snapshot_id = random_snapshot(snapshots)
                  result, _ = import_from_url(uri, token, servicename["service"], header, snapshot_id)
                  sleep(rand * PAUSE_TIME)
                end
              else 
	        snapshots = list_snapshot(uri, token, servicename["service"], header)
                if has_snapshot?(snapshots) 
                  snapshot_id = random_snapshot(snapshots)
                  result = import_from_data(uri, token, servicename["service"], header, snapshot_id)
                  sleep(rand * PAUSE_TIME)
		end
              end
	    end
	  end
	end
      end
    end
  end
end
threads.each { |t| t.join }
duration = Time.now - now
$log.info("testing execution duration: #{duration / 60.0 / 60.0} hours")
print_results()
