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
require "json"

$:.unshift(File.join(File.dirname(__FILE__), "lib"))
require "helper"
$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

include App::Helper
# get job status
get '/snapshot/queryjobstatus' do
  begin
    token       = params[:token]
    service     = params[:service]
    job_id      = params[:jobid]
    $log.info("query job status. service name: #{service}")
    
    parse_header
    job = get_job(token, service, job_id)
    job.to_json
  rescue Exception => e
    $log.error("*** FATAL UNHANDLED EXCEPTION ***")
    $log.error("e: #{e.inspect}")
    $log.error("at@ #{e.backtrace.join("\n")}")
    raise e
  end
end

#create snapshot
post '/snapshot/create' do
  begin
    token       = params[:token]
    service     = params[:service]
    $log.info("token: #{token}, service name: #{service}")
    
    parse_header
    resp = create_snapshot(token, service)
    
    resp
  rescue Exception => e
    $log.error("*** FATAL UNHANDLED EXCEPTION ***")
    $log.error("e: #{e.inspect}")
    $log.error("at@ #{e.backtrace.join("\n")}")
    raise e
  end
end

#list snapshots
post '/snapshot/list' do
  begin
    token       = params[:token]
    service     = params[:service]
    snapshot_id = params[:snapshotid]
    $log.info("List snapshot: Service name: #{service}, #{snapshot_id.nil?}")

    parse_header
    if snapshot_id==nil || snapshot_id == ""
      $log.debug("get_snapshots called")
      resp = get_snapshots(token, service)
    else
      $log.debug("get_snapshot called")
      resp = get_snapshot(token, service, snapshot_id)
    end
    resp
  rescue Exception => e
    $log.error("*** FATAL UNHANDLED EXCEPTION ***")
    $log.error("e: #{e.inspect}")
    $log.error("at@ #{e.backtrace.join("\n")}")
    raise e
  end
end

#rollbak snapshot
post '/snapshot/rollback' do
  begin
    token       = params[:token]
    service     = params[:service]
    snapshot_id = params[:snapshotid]

    parse_header

    resp = rollback_snapshot(token, service, snapshot_id)
    resp
  rescue Exception => e
    $log.error("*** FATAL UNHANDLED EXCEPTION ***")
    $log.error("e: #{e.inspect}")
    $log.error("at@ #{e.backtrace.join("\n")}")
    raise e
  end
end

post '/snapshot/createurl' do
  token       = params[:token]
  service     = params[:service]
  snapshot_id = params[:snapshotid]

  parse_header

  create_serialized_url(token, service, snapshot_id)
end

#import service from url
post '/snapshot/importurl' do
  begin
    token       = params[:token]
    service     = params[:service]
    snapshot_id = params[:snapshotid]

    parse_header
    request.body.rewind
    body = JSON.parse(request.body.read)
    serialized_url = body["url"]

    import_service_from_url(token, service, serialized_url)

  rescue Exception => e
    $log.error("*** FATAL UNHANDLED EXCEPTION ***")
    $log.error("e: #{e.inspect}")
    $log.error("at@ #{e.backtrace.join("\n")}")
    raise e
  end
end

#import service from data
post '/snapshot/importdata' do
  begin
    token       = params[:token]
    service     = params[:service]
    snapshot_id = params[:snapshotid]

    parse_header

    request.body.rewind
    body = JSON.parse(request.body.read)
    serialized_url = body["url"]

    $log.debug("import data. serialized_url: #{serialized_url}")
    serialized_data = download_data(serialized_url)
    import_service_from_data(token, service, serialized_data)
  rescue Exception => e
    $log.error("*** FATAL UNHANDLED EXCEPTION ***")
    $log.error("e: #{e.inspect}")
    $log.error("at@ #{e.backtrace.join("\n")}")
    raise e
  end
end

#delete snapshot
post '/snapshot/delete' do
  begin
    token       = params[:token]
    service     = params[:service]
    snapshot_id = params[:snapshotid]

    parse_header

    delete_snapshot(token, service, snapshot_id)
  rescue Exception => e
    $log.error("*** FATAL UNHANDLED EXCEPTION ***")
    $log.error("e: #{e.inspect}")
    $log.error("at@ #{e.backtrace.join("\n")}")
    raise e
  end
end
