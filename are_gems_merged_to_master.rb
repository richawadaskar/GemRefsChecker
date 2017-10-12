require "bundler"
require "rest-client"
require "json"

def put_warnings(warnings)
  unless warnings.empty?
    warn "\nThe following invoca gems in the gemfile are not pointing to the tip of their master branches."
    warnings.sort_by{|warning| warning["name"]}.each do |gem|
      puts gem
    end
  end
end

def put_errors(errors)
  unless errors.empty?
    puts "\nThe shas of the following gems are not in their master branches."
    puts "Merge the gems into their respective master branches, update the Gemfile, bundle install, then try again."
    errors.sort_by{|error| error["name"]}.each do |gem|
      puts gem
    end
  end
end

def call_github_api(username, password, path)
  JSON.parse(RestClient.get("https://#{username}:#{password}@api.github.com/repos/Invoca/#{path}"))
end

def repo_is_forked(username, password, gem_name)
  call_github_api(username, password, gem_name)["fork"]
end

def compare_sha_with_master(username, password, gem_name, sha)
  result = call_github_api(username, password, "#{gem_name}/compare/master...#{sha}")
  {ahead_by: result["ahead_by"], behind_by: result["behind_by"]}
end

def show_env_setup_and_exit
  puts('GITHUB_USERNAME and GITHUB_PASSWORD must be defined in the environment')
  exit(1)
end

def is_gem_merged_to_master(username, password, source, errors, warnings)
  gem_name = source.name
  sha = source.revision
  unless repo_is_forked(username, password, gem_name)
    result = compare_sha_with_master(username, password, gem_name, sha)
    if result[:ahead_by] > 0
      errors << { name: gem_name, ahead_by: result[:ahead_by], sha: sha }
    elsif result[:behind_by] > 0
      warnings << { name: gem_name, behind_by: result[:behind_by], sha: sha }
    end
  end
rescue RestClient::Exception => ex
  puts "An error occurred while checking on the status of gem #{gem_name}"
  puts "#{ex.http_code}: #{ex.http_body}"
end

def check_if_gems_are_merged_to_master(username, password)
  lock = Bundler.read_file(Bundler.default_lockfile)
  gems = Bundler::LockfileParser.new(lock)

  errors = []
  warnings = []
  gems.sources.select{ |s| s.class == Bundler::Source::Git }.each do |source|
    is_gem_merged_to_master(username, password, source, errors, warnings)
  end
  {errors: errors, warnings: warnings}
end

username = ENV['GITHUB_USERNAME'] or show_env_setup_and_exit
password = ENV['GITHUB_PASSWORD'] or show_env_setup_and_exit

result = check_if_gems_are_merged_to_master(username, password)
put_warnings(result[:warnings])
put_errors(result[:errors])
exit result[:errors].empty? ? 0 : 1
