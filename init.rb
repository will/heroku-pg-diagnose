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
      response = Excon.get("#{DIAGNOSE_URL}/reports/#{db_id}")
      report = JSON.parse(response.body)
      puts "PG Diagnose report created #{report["created_at"]}"
    else
      response = generate_report(db_id)
      report = JSON.parse(response.body)
      puts "PG Diagnose report available for 1 month at:"
    end
    puts "#{DIAGNOSE_URL}/reports/#{report["id"]}"
    puts

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

    params = {'url' => attachment.url}

    return Excon.post("#{DIAGNOSE_URL}/reports", :body => params.to_json)
  end

  def process_checks(status, checks)
    return unless checks.size > 0
    color_code = { "red" => 31, "green" => 32, "yellow" => 33 }.fetch(status, 35)

    checks.each do |check|
      puts "\e[#{color_code}m#{status.upcase}: #{check['name']}\e[0m"
      results = check['results']
      if results && results.size > 0
        display_table(
          results,
          results.first.keys,
          results.first.keys.map{ |field| field.split(/_/).map(&:capitalize).join(' ') }
        )
        puts
      end
    end
  end

end