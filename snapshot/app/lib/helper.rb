require "json"
require "curb"

module App
  module Helper
    def parse_header
      @app    = env['HTTP_APP']? env['HTTP_APP'] : "lifeworker"
      @target = env['HTTP_TARGET']? env['HTTP_TARGET'] : "http://api.cf110.dev.las01.vcsops.com"
    end

    def auth_headers(token)
      {"content-type"=>"application/json", "AUTHORIZATION" => token}
    end 

    def get_job(token, service_id, job_id)
      easy = Curl::Easy.new("#{@target}/services/v1/configurations/#{service_id}/jobs/#{job_id}")
      easy.headers = auth_headers(token)
      easy.resolve_mode =:ipv4
      easy.http_get

      resp = easy.body_str
      $log.debug("get job. response: #{resp.inspect}")
      JSON.parse(resp)
    end

    def get_snapshots(token, service_id)
      easy = Curl::Easy.new("#{@target}/services/v1/configurations/#{service_id}/snapshots")
      easy.headers = auth_headers(token)
      easy.resolve_mode =:ipv4
      easy.http_get

      if easy.response_code == 501
        pending "Snapshot extension is disabled, return code=501"
      elsif easy.response_code != 200
        raise "code:#{easy.response_code}, body:#{easy.body_str}"
      end

      resp = easy.body_str
      $log.debug("list snapshots. url: #{easy.url}, resp: #{resp}")
      JSON.parse(resp)
      resp
    end
    
    def get_snapshot(token, service_id, snapshot_id)
      easy = Curl::Easy.new("#{@target}/services/v1/configurations/#{service_id}/snapshots/#{snapshot_id}")
      easy.headers = auth_headers(token)
      easy.resolve_mode =:ipv4
      easy.http_get

      resp = easy.body_str
      JSON.parse(resp)

      resp
    end

    def create_snapshot(token, service_id)
      $log.debug("service id: #{service_id}")
      url = "#{@target}/services/v1/configurations/#{service_id}/snapshots"
      easy = Curl::Easy.new(url)
      easy.headers = auth_headers(token)
      easy.resolve_mode =:ipv4
      easy.http_post
      
      resp = easy.body_str
      $log.info("create snapshot. url: #{url}, hearder: #{auth_headers(token)}, response body: #{easy.body_str}")
      resp
    end

    def rollback_snapshot(token, service_id, snapshot_id)
      $log.debug("rollback snapshot. service id: #{service_id}, snapshot id: #{snapshot_id}")
      url = "#{@target}/services/v1/configurations/#{service_id}/snapshots/#{snapshot_id}"
      easy = Curl::Easy.new(url)
      easy.headers = auth_headers(token)
      easy.resolve_mode =:ipv4
      easy.http_put ''

      resp = easy.body_str
      $log.debug("rollback snapshot. url: #{url}, hearder: #{auth_headers(token)}, response body: #{easy.body_str}")
      resp
    end

    def delete_snapshot(token, service_id, snapshot_id)
      $log.debug("delete snapshot. service id: #{service_id}, snapshot id: #{snapshot_id}")
      url = "#{@target}/services/v1/configurations/#{service_id}/snapshots/#{snapshot_id}"
      easy = Curl::Easy.new(url)
      easy.headers = auth_headers(token)
      easy.resolve_mode =:ipv4
      easy.http_delete
        
      resp = easy.body_str
      $log.debug("delete snapshot. url: #{url}, hearder: #{auth_headers(token)}, response body: #{easy.body_str}")

      resp
    end

    def get_serialized_url(token, service_id, snapshot_id)
      easy = Curl::Easy.new("#{@target}/services/v1/configurations/#{service_id}/serialized/url/snapshots/#{snapshot_id}")
      easy.headers = auth_headers(token)
      easy.resolve_mode =:ipv4
      easy.http_get
    
      if easy.response_code == 501
        pending "Serialized API is disabled, return code=501"
      elsif easy.response_code != 200
        return nil
      end
      
      resp = easy.body_str
      result = JSON.parse(resp)
      result["url"]
    end

    def download_data(serialized_url)
      temp_file = Tempfile.new("serialized_data")
      $log.info("The temp file path: #{temp_file.path}")
      File.open(temp_file.path, "wb+") do |f|
        c = Curl::Easy.new(serialized_url)
        c.on_body{|data| f.write(data)}
        c.perform
        #c.response_code.should == 200
        $log.debug("download data. url: #{c.url}, response: #{c.response_code}")
      end
        
      File.open(temp_file.path) do |f|
        $log.debug("serialized data size: #{f.size / 1024 / 1024}MB")#f.size.should > 0
      end
      serialized_data_file = temp_file
    end

    def import_service_from_url(token, service_id, serialized_url)
      easy = Curl::Easy.new("#{@target}/services/v1/configurations/#{service_id}/serialized/url")
      easy.headers = auth_headers(token)
      payload = {"url" => serialized_url}
      easy.resolve_mode =:ipv4
      easy.http_put(JSON payload)
      
      resp = easy.body_str
      resp
    end

    def import_service_from_data(token, service_id, serialized_data)
      post_data = []
      post_data << Curl::PostField.content("_method", "put")
      post_data << Curl::PostField.file("data_file", serialized_data.path)
      $log.info("post data: #{post_data.inspect}")
      $log.info("serialized data: #{serialized_data.inspect}, serialized data path: #{serialized_data.path.inspect}")
      easy = Curl::Easy.new("#{@target}/services/v1/configurations/#{service_id}/serialized/data")
      easy.multipart_form_post = true
      easy.headers = {"AUTHORIZATION" => token}
      easy.resolve_mode =:ipv4
      $log.info("easy request: #{easy.inspect}")
      easy.http_post(post_data)
    
      resp = easy.body_str
      $log.info("import data. service id: #{service_id}, serialized_data: #{serialized_data.path}, resp: #{resp}")
    
      #delete the temp file
      serialized_data.unlink
    
      resp
    end

    def create_serialized_url(token, service_id, snapshot_id)
      easy = Curl::Easy.new("#{@target}/services/v1/configurations/#{service_id}/serialized/url/snapshots/#{snapshot_id}")
      easy.headers = auth_headers(token)
      easy.resolve_mode =:ipv4
      easy.http_post ''
  
      resp = easy.body_str
    end
  end
end

