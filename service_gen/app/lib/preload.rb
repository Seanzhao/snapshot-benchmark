require 'rubygems'
require 'sinatra'
require 'mysql2'
require 'logger'
require 'json'

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG
TABLE_NAME="data_table"
MAX_BIN_LENGTH = 1024;

module App
  module Preload
    def create_db(service_name)
      $log.debug("create_db_called")
      eval("create_#{service_name}")
    end
    
    def insert_data(service_name)
      clients = get_clients(service_name)
      data, ind = provision_data
      insert_to(service_name, clients, data, ind)
    end
    
    def get_clients(service_name)
      clients = nil
      eval("clients = get_#{service_name}_clients")
      $log.debug("get_clients. #{service_name} clients: #{clients.inspect}")
      clients
    end
    
    def insert_to(service_name, clients, data, ind)
      eval("insert_to_#{service_name}(clients, data, ind)")
    end
    
    def load_service(service_name)
      services = JSON.parse(ENV['VCAP_SERVICES'])
      service_instances = []
      services.each do |k,v|
        v.each do |s|
          if k.split('-')[0].downcase == service_name.downcase
            service_instances << s["credentials"]
          end
        end
      end
      $log.debug("The service instances are loaded: #{service_instances}")
      service_instances
    end
    
    def create_mongodb
    end
    
    def create_mysql
      clients = get_mysql_clients
      clients.each do |client|
        $log.debug("create_mysql. client: #{client.inspect}")
        result = client.query("SELECT table_name FROM information_schema.tables WHERE table_name = '#{TABLE_NAME}'");
        $log.debug("result: #{result.count}")
        result = client.query("CREATE table IF NOT EXISTS #{TABLE_NAME} " +
                            "( id MEDIUMINT NOT NULL AUTO_INCREMENT PRIMARY KEY, " + 
                            "data VARBINARY(#{MAX_BIN_LENGTH}), ind varchar(20));") if result.count != 1
        $log.info("create table: #{TABLE_NAME}. result: #{result.inspect}, client: #{client.inspect}")
        client.close
      end
      {:state => "OK", :client => clients.inspect}.to_json
    end

    def create_postgresql
      clients = get_postgresql_clients
      clients.each do |client|
        $log.debug("create_postgresql_datastore. client: #{client.inspect}")
        result = client.query("create table #{TABLE_NAME} (id varchar(20), data text);") if client.query("select * from pg_catalog.pg_class where relname = '#{TABLE_NAME}';").num_tuples() < 1
        $log.info("create table: #{TABLE_NAME}. result: #{result.inspect}, client: #{client.inspect}")
        client.close
      end
      {:state => "OK", :client => clients.inspect}.to_json
    end

    def create_redis
    end

    def get_mongodb_clients
      mongodb_services = load_service('mongodb')
      colls=[]
      mongodb_services.each do |mongodb_service|
        conn = Mongo::Connection.new(mongodb_service['hostname'], mongodb_service['port'])
        $log.debug("Connect to mongodb: #{conn.inspect}")
        db = conn[mongodb_service['db']]
        colls << db[TABLE_NAME] if db.authenticate(mongodb_service['username'], mongodb_service['password'])
      end
      colls
    end
    
    def get_mysql_clients
      mysql_services = load_service('mysql')
      colls=[]
      mysql_services.each do |mysql_service|
        colls << Mysql2::Client.new(:host => mysql_service['hostname'],
                                    :username => mysql_service['user'],
                                    :port => mysql_service['port'],
                                    :password => mysql_service['password'],
                                    :database => mysql_service['name'])
      end
      colls
    end

    def get_postgresql_clients
      postgresql_services = load_service('postgresql')
      colls=[]
      postgresql_services.each do |postgresql_service|
        colls << PGconn.open(postgresql_service['host'],
	                     postgresql_service['port'],
	                     :dbname => postgresql_service['name'],
	                     :user => postgresql_service['username'],
	                     :password => postgresql_service['password'])
      end	
      colls
    end

    def get_redis_clients
      redis_services = load_service('redis')
      colls = []
      redis_services.each do |redis_service|
      colls << Redis.new(:host => redis_service['host'],
                         :port => redis_service['port'],
                         :user => redis_service['username'],
                         :password => redis_service['password'])
      end
      colls
    end

    def insert_to_mongodb(clients, data, ind)
      clients.each do |client|
        client.insert({ '_id' => ind, 'data' => data })
      end
      $log.info("insert data to mongodb. client: #{clients.inspect}, data: #{data}, ind: #{ind}")
    end
    
    def insert_to_mysql(clients, data, ind)
      clients.each do |client|
        client.query("insert into #{TABLE_NAME} (data, ind) values ('#{data}', '#{ind}');")
      end
      $log.info("insert data to mysql. client: #{clients.inspect}, data: #{data}, ind: #{ind}")
    end

    def insert_to_postgresql(clients, data, ind)
      clients.each do |client|
        client.query("insert data to #{TABLE_NAME} (ind, data) values ('#{ind}', '#{data}')")
      end
      $log.info("insert data to postgresql. client: #{clients.inspect}, data: #{data}, ind: #{ind}")
    end

    def insert_to_redis(clients, data, ind)
      clients.each do |client|
        client.set(ind, data)
      end
      $log.info("insert data to redis. client: #{clients.inspect}, key: #{ind}, data size: #{data.size}")
    end

    def provision_data
      ["testdata", Time.now.usec]
    end
  end
end
