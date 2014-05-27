major, minor, _ = Heroku::VERSION.split(/\./).map(&:to_i)
if major > 3
  # ok
elsif major == 3 && minor >= 4
  # ok
else
    $stderr.puts(Heroku::Helpers.format_with_bang(<<-EOM))
The heroku-pg-extras plugin was not loaded.
It requires Heroku CLI version >= 3.4.0. You are using #{Heroku::VERSION}.
EOM
end

class Heroku::Command::Pg < Heroku::Command::Base
  DIAGNOSE_URL = ENV.fetch('PGDIAGNOSE_URL', "https://pgdiagnose.herokuapp.com")
  # pg:diagnose [DATABASE|REPORT_ID]
  #
  # run diagnostics report on DATABASE
  #
  # defaults to DATABASE_URL databases if no DATABASE is specified
  # if REPORT_ID is specified instead, a previous report id displayed
  def diagnose
    db_id = shift_argument

    if db_id =~ /\A[a-z0-9\-]{36}\z/
      response = Excon.get("#{DIAGNOSE_URL}/reports/#{db_id}", :headers => {"Content-Type" => "application/json"})
      report = JSON.parse(response.body)
      puts "PG Diagnose report created #{report["created_at"]}"
    else
      response = generate_report(db_id)
      report = JSON.parse(response.body)
      puts "PG Diagnose report available for 1 month at:"
    end
    puts "#{DIAGNOSE_URL}/reports/#{report["id"]}"

    c = report['checks']
    process_checks 'red',     c.select{|f| f['status'] == 'red'}
    process_checks 'yellow',  c.select{|f| f['status'] == 'yellow'}
    process_checks 'green',   c.select{|f| f['status'] == 'green'}
    process_checks 'unknown', c.reject{|f| %w(red yellow green).include?(f['status'])}
  end

  private
  def generate_report(db_id)
    attachment = generate_resolver.resolve(db_id, "DATABASE_URL")
    validate_arguments!

    @uri = URI.parse(attachment.url) # for nine_two?
    if !nine_two?
      error("pg:diagnose is only available on Postgres version >= 9.2")
    end

    logs_url = heroku.get("/apps/#{attachment.app}/logs?logplex=true&ps=heroku-postgres").to_s

    params = {
      'url'  => attachment.url,
      'plan' => attachment.plan,
      'logs' => logs_url,
      'app'  => attachment.app,
      'database' => attachment.config_var
    }

    return Excon.post("#{DIAGNOSE_URL}/reports", :body => params.to_json, :headers => {"Content-Type" => "application/json"})
  end

  def process_checks(status, checks)
    color_code = { "red" => 31, "green" => 32, "yellow" => 33 }.fetch(status, 35)
    return unless checks.size > 0


    checks.each do |check|
      status = check['status']
      puts "\e[#{color_code}m#{status.upcase}: #{check['name']}\e[0m"
      next if "green" == status

      results = check['results']
      return unless results && results.size > 0

      if results.first.kind_of? Array
        puts "  " + results.first.map(&:capitalize).join(" ")
      else
        display_table(
          results,
          results.first.keys,
          results.first.keys.map{ |field| field.split(/_/).map(&:capitalize).join(' ') }
        )
      end
      puts
    end
  end

end
