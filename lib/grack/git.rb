module Grack
  class Git
    attr_reader :repo
    def initialize(git_path, repo_path)
      @git_path = git_path
      @repo = repo_path
      @repo = nil unless valid_git_dir?
    end

    def update_server_info
      execute(%W(update-server-info))
    end

    def command(cmd)
      [@git_path || 'git'] + cmd
    end

    def capture(cmd)
      IO.popen(popen_env, cmd, popen_options).read
    end

    def execute(cmd)
      capture( command(cmd) ).chomp
    end

    def execute_with_block(cmd)
      IO.popen(popen_env, command(cmd), File::RDWR, popen_options) do |pipe|
        yield(pipe)
      end
    end

    def popen_options
      {chdir: repo, unsetenv_others: true}
    end

    def popen_env
      {'PATH' => ENV['PATH'], 'GL_ID' => ENV['GL_ID']}
    end

    def config_setting(service_name)
      service_name = service_name.gsub('-', '')
      setting = config("http.#{service_name}")
      if service_name == 'uploadpack'
        return setting != 'false'
      else
        return setting == 'true'
      end
    end

    def config(config_name)
      execute(%W(config #{config_name}))
    end

    def valid_git_dir?
      '.' == execute(%W(rev-parse --git-dir))
    end
  end
end
