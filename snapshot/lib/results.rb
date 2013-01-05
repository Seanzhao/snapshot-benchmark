require "sqlite3"

module Results
  module_function

  RESULTS_TABLE = "results"
  RESULT_DB     = "results.db"

  def create_results()
    File.delete(RESULT_DB) if File.exists?(RESULT_DB)

    $db = SQLite3::Database.open(RESULT_DB)
    $db.execute("create table if not exists #{RESULTS_TABLE}(id integer primary key," +
                    " time TIMESTAMP, op text, result text, duration integer);")
    $log.debug("create results db. db: #{$db.inspect}")
  end

  def insert_result(operation, result, duration)
    time = Time.now
    $log.debug("insert result. time: #{time}, operation: #{operation}, result: #{result}, duration: #{duration}")
    @lock ||= Mutex.new
    @lock.synchronize do
      $db.execute("insert into results (time, op, result, duration)" +
                      " values ('#{time}', '#{operation}', '#{result}', #{duration})")
    end
  end

  def print_results()
    puts "\tOperation\t\tError Rate\t\n"
    $log.info("Operation,Error Rate")
    ops = $db.execute("select op from #{RESULTS_TABLE} group by op")
    $log.debug("SQL: select op from #{RESULTS_TABLE} group by op, result: #{ops.inspect}")
    ops.each do |op|
      op = op.first
      failures = $db.execute("select count(op) from #{RESULTS_TABLE} where op = '#{op}' and result = 'fail'").first.first
      $log.debug("failures: #{failures.class}, #{failures.inspect}")
      total = $db.execute("select count(op) from #{RESULTS_TABLE} where op = '#{op}'").first.first
      duration = $db.execute("select max(duration) from #{RESULTS_TABLE} where op = '#{op}'").first.first
      $log.debug("total: #{total.class}, #{total.inspect}")
      if total > 0
        puts "\t#{op}\t\t#{failures}/#{total} (#{failures * 100.0 / total}%)\tMax duration: #{duration}\t\n"
        $log.info("\t#{op}\t\t#{failures}/#{total} (#{failures * 100.0 / total}%)\tMax duration: #{duration}\t")
      else
        puts "\t#{op}\t\t#{failures}/#{total} (0.0%)\tMax duration: #{duration}\t\n"
        $log.info("\t#{op}\t\t#{failures}/#{total} (0.0%)\tMax duration: #{duration}\t")
      end

    end

  end

  private
end
