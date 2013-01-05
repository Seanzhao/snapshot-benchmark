require "logger"
require "cfoundry"
require "yaml"

$:.unshift(File.join(File.dirname(__FILE__), "lib"))
require "utils"

CONFIG = File.join(File.dirname(__FILE__), "config/service_gen.yml")
puts CONFIG.inspect
conf = YAML.load_file(CONFIG)
puts conf.inspect
target = conf["target"]
users = conf["users"]
cleanup = conf ["cleanup"]
user_number = conf["user_number"]
threads = []
user_number.times do |i| 
  threads << Thread.new do
  include Utils
  token, client = login(target, users[i]["email"], users[i]["password"])
  if cleanup == true
    cleanup(client)
  end
  app = push_app(users[i]["application"], client)
  uri = app.urls.first
  puts uri
  service_name =  users[i]["application"]["service"]
  puts service_name
  create_db(uri, service_name)
  preload_data(uri,service_name)
  end
end
threads.each {|t| t.join}

