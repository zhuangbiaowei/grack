module Grack
  class Git
    attr_reader :repo

    def initialize(git_path, repo_path)
      @git_path = git_path
      @repo = repo_path
    end

    def update_server_info
      execute(%W(update-server-info))
    end

    def command(cmd)
      [@git_path || 'git'] + cmd
    end

    def capture(cmd)
      # _Not_ the same as `IO.popen(...).read`
      # By using a block we tell IO.popen to close (wait for) the child process
      # after we are done reading its output.
      IO.popen(popen_env, cmd, popen_options) { |p| p.read }
    end

    def execute(cmd)
      cmd = command(cmd)
      if block_given?
        IO.popen(popen_env, cmd, File::RDWR, popen_options) do |pipe|
          yield(pipe)
        end
      else
        capture(cmd).chomp
      end
    end

    def popen_options
      { chdir: repo, unsetenv_others: true }
    end

    def popen_env
      { 'PATH' => ENV['PATH'], 'GL_ID' => ENV['GL_ID'] }
    end

    def config_setting(service_name)
      service_name = service_name.gsub('-', '')
      setting = config("http.#{service_name}")

      if service_name == 'uploadpack'
        setting != 'false'
      else
        setting == 'true'
      end
    end

    def config(config_name)
      execute(%W(config #{config_name}))
    end

    def valid_repo?
      return false unless File.exists?(repo) && File.realpath(repo) == repo

      match = execute(%W(rev-parse --git-dir)).match(/\.$|\.git$/)
      
      if match.to_s == '.git'
        # Since the parent could be a git repo, we want to make sure the actual repo contains a git dir.
        return false unless Dir.entries(repo).include?('.git')
      end

      match
    end
  end
end
