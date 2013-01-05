require 'sinatra' 
require 'redis' 
require 'json' 
require 'mongo' 
require 'mysql2' 
require 'carrot' 
require 'uri' 
require 'pg' 
require 'curb' 
require "logger" 
$:.unshift(File.join(File.dirname(__FILE__), "lib"))                     
require "preload"

include App::Preload

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

post '/createdb' do
  service_name = params[:service]
  $log.debug("/createdb. service: #{service_name}")
  create_db(service_name)
end

put '/insertdata' do
  service_name = params[:service]
  $log.debug("/insertdata. service: #{service_name}")
  insert_data(service_name)
end

