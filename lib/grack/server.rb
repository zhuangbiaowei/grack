require 'zlib'
require 'rack/request'
require 'rack/response'
require 'rack/utils'
require 'time'

require 'grack/git'

module Grack
  class Server
    attr_reader :git

    SERVICES = [
      ["POST", 'service_rpc',      "(.*?)/git-upload-pack$",  'upload-pack'],
      ["POST", 'service_rpc',      "(.*?)/git-receive-pack$", 'receive-pack'],

      ["GET",  'get_info_refs',    "(.*?)/info/refs$"],
      ["GET",  'get_text_file',    "(.*?)/HEAD$"],
      ["GET",  'get_text_file',    "(.*?)/objects/info/alternates$"],
      ["GET",  'get_text_file',    "(.*?)/objects/info/http-alternates$"],
      ["GET",  'get_info_packs',   "(.*?)/objects/info/packs$"],
      ["GET",  'get_text_file',    "(.*?)/objects/info/[^/]*$"],
      ["GET",  'get_loose_object', "(.*?)/objects/[0-9a-f]{2}/[0-9a-f]{38}$"],
      ["GET",  'get_pack_file',    "(.*?)/objects/pack/pack-[0-9a-f]{40}\\.pack$"],
      ["GET",  'get_idx_file',     "(.*?)/objects/pack/pack-[0-9a-f]{40}\\.idx$"],

      ["GET",  'get_gvfs_config',  "(.*?)/gvfs/config"],
      ["POST", 'get_gvfs_objects', "(.*?)/gvfs/objects$"],
      ["POST", 'get_gvfs_size',    "(.*?)/gvfs/sizes"],
      ["GET",  'get_gvfs_prefetch',"(.*?)/gvfs/prefetch"],
      ["GET",  'get_gvfs_object',  "(.*?)/gvfs/objects/[0-9a-fA-F]{40}$"],
    ]

    def initialize(config = false)
      set_config(config)
    end

    def set_config(config)
      @config = config || {}
    end

    def set_config_setting(key, value)
      @config[key] = value
    end

    def call(env)
      dup._call(env)
    end

    def _call(env)
      @env = env
      @req = Rack::Request.new(env)

      cmd, path, @reqfile, @rpc = match_routing

      return render_method_not_allowed if cmd == 'not_allowed'
      return render_not_found unless cmd

      @git = get_git(path)
      return render_not_found unless git.valid_repo?

      self.method(cmd).call
    end

    # ---------------------------------
    # actual command handling functions
    # ---------------------------------

    # Uses chunked (streaming) transfer, otherwise response
    # blocks to calculate Content-Length header
    # http://en.wikipedia.org/wiki/Chunked_transfer_encoding

    CRLF = "\r\n"

    def service_rpc
      return render_no_access unless has_access?(@rpc, true)

      input = read_body

      @res = Rack::Response.new
      @res.status = 200
      @res["Content-Type"] = "application/x-git-%s-result" % @rpc
      @res["Transfer-Encoding"] = "chunked"
      @res["Cache-Control"] = "no-cache"

      @res.finish do
        git.execute([@rpc, '--stateless-rpc', git.repo]) do |pipe|
          pipe.write(input)
          pipe.close_write

          while block = pipe.read(8192)     # 8KB at a time
            @res.write encode_chunk(block)  # stream it to the client
          end

          @res.write terminating_chunk
        end
      end
    end

    def encode_chunk(chunk)
      size_in_hex = chunk.size.to_s(16)
      [size_in_hex, CRLF, chunk, CRLF].join
    end

    def terminating_chunk
      [0, CRLF, CRLF].join
    end

    def get_gvfs_config

      puts @req.inspect

      @res = Rack::Response.new
      @res.status = 200
      @res["Content-Type"] = "text/html;charset=utf-8"
      @res.write("{\"AllowedGvfsClientVersions\":null}")
      @res.finish
    end

    def get_gvfs_objects
      input = read_body
      puts input
      req = parse_req(input)
      obj_id_list = get_obj_id_list(git,req)
      file_name = pack_file(git,obj_id_list)
      send_file(file_name, "application/x-git-packfile") do 
        hdr_cache_forever
      end
    end

    def get_gvfs_size
      input = read_body
      obj_list = parse_req(input)
      obj_sizes = get_obj_size(git,obj_list)
      @res = Rack::Response.new
      @res.status = 200
      @res["Content-Type"] = "application/json"
      @res.write(obj_sizes.to_json)
      @res.finish
    end

    def get_gvfs_prefetch
      lastPackTimestamp = @req.query_string.gsub("lastPackTimestamp=","").to_i
      packfile_list = get_packfile_list(git,lastPackTimestamp)
      obj_id_list = get_packed_objs(git,packfile_list)
      file_name = pack_file(git,obj_id_list)
      tmp_file = File.new(file_name+".add","wb")
      tmp_file.write("GPRE \x01\x01\x00")
      time = File.mtime(file_name).to_i.to_s(16)
      tmp_file.write(time[6..7].to_i(16).chr)
      tmp_file.write(time[4..5].to_i(16).chr)
      tmp_file.write(time[2..3].to_i(16).chr)
      tmp_file.write(time[0..1].to_i(16).chr)
      tmp_file.write("\x00\x00\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x7F\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF")
      body = File.binread(file_name)
      tmp_file.write body
      tmp_file.close
      send_file(file_name+".add", "application/x-gvfs-timestamped-packfiles-indexes") do 
        hdr_cache_forever
      end
    end

    def get_gvfs_object
      @reqfile.gsub!("gvfs/","")
      @reqfile = @reqfile[0..9]+"/"+@reqfile[10..-1]
      send_file(@reqfile, "application/x-git-loose-object") do
        hdr_cache_forever
      end
    end
    
    def get_info_refs
      service_name = get_service_type
      return dumb_info_refs unless has_access?(service_name)

      refs = git.execute([service_name, '--stateless-rpc', '--advertise-refs', git.repo])

      @res = Rack::Response.new
      @res.status = 200
      @res["Content-Type"] = "application/x-git-%s-advertisement" % service_name
      hdr_nocache

      @res.write(pkt_write("# service=git-#{service_name}\n"))
      @res.write(pkt_flush)
      @res.write(refs)

      @res.finish
    end

    def dumb_info_refs
      git.update_server_info
      send_file(@reqfile, "text/plain; charset=utf-8") do
        hdr_nocache
      end
    end

    def get_info_packs
      # objects/info/packs
      send_file(@reqfile, "text/plain; charset=utf-8") do
        hdr_nocache
      end
    end

    def get_loose_object
      send_file(@reqfile, "application/x-git-loose-object") do
        hdr_cache_forever
      end
    end

    def get_pack_file
      send_file(@reqfile, "application/x-git-packed-objects") do
        hdr_cache_forever
      end
    end

    def get_idx_file
      send_file(@reqfile, "application/x-git-packed-objects-toc") do
        hdr_cache_forever
      end
    end

    def get_text_file
      send_file(@reqfile, "text/plain") do
        hdr_nocache
      end
    end

    # ------------------------
    # logic helping functions
    # ------------------------

    # some of this borrowed from the Rack::File implementation
    def send_file(reqfile, content_type)      
      reqfile = File.join(git.repo, reqfile)
      return render_not_found unless File.exists?(reqfile)

      return render_not_found unless reqfile == File.realpath(reqfile)

      # reqfile looks legit: no path traversal, no leading '|'

      @res = Rack::Response.new
      @res.status = 200
      @res["Content-Type"]  = content_type
      @res["Last-Modified"] = File.mtime(reqfile).httpdate

      yield

      if size = File.size?(reqfile)
        @res["Content-Length"] = size.to_s
        @res.finish do
          File.open(reqfile, "rb") do |file|
            while part = file.read(8192)
              @res.write part
            end
          end
        end
      else
        body = [File.read(reqfile)]
        size = Rack::Utils.bytesize(body.first)
        @res["Content-Length"] = size
        @res.write body
        @res.finish
      end
    end

    def get_git(path)
      root = @config[:project_root] || Dir.pwd
      path = File.join(root, path)
      Grack::Git.new(@config[:git_path], path)
    end

    def get_service_type
      service_type = @req.params['service']
      return false unless service_type
      return false if service_type[0, 4] != 'git-'
      service_type.gsub('git-', '')
    end

    def match_routing
      cmd = nil
      path = nil

      SERVICES.each do |method, handler, match, rpc|
        next unless m = Regexp.new(match).match(@req.path_info)

        return ['not_allowed'] unless method == @req.request_method

        cmd = handler
        path = m[1]
        file = @req.path_info.sub(path + '/', '')

        return [cmd, path, file, rpc]
      end
      
      nil
    end

    def has_access?(rpc, check_content_type = false)
      if check_content_type
        conten_type = "application/x-git-%s-request" % rpc
        return false unless @req.content_type == conten_type
      end

      return false unless ['upload-pack', 'receive-pack'].include?(rpc)

      if rpc == 'receive-pack'
        return @config[:receive_pack] if @config.include?(:receive_pack)
      end

      if rpc == 'upload-pack'
        return @config[:upload_pack] if @config.include?(:upload_pack)
      end

      git.config_setting(rpc)
    end

    def read_body
      if @env["HTTP_CONTENT_ENCODING"] =~ /gzip/
        Zlib::GzipReader.new(@req.body).read
      else
        @req.body.read
      end
    end

    # --------------------------------------
    # HTTP error response handling functions
    # --------------------------------------

    PLAIN_TYPE = { "Content-Type" => "text/plain" }

    def render_method_not_allowed
      if @env['SERVER_PROTOCOL'] == "HTTP/1.1"
        [405, PLAIN_TYPE, ["Method Not Allowed"]]
      else
        [400, PLAIN_TYPE, ["Bad Request"]]
      end
    end

    def render_not_found
      [404, PLAIN_TYPE, ["Not Found"]]
    end

    def render_no_access
      [403, PLAIN_TYPE, ["Forbidden"]]
    end


    # ------------------------------
    # packet-line handling functions
    # ------------------------------

    def pkt_flush
      '0000'
    end

    def pkt_write(str)
      (str.size + 4).to_s(16).rjust(4, '0') + str
    end

    # ------------------------
    # header writing functions
    # ------------------------

    def hdr_nocache
      @res["Expires"] = "Fri, 01 Jan 1980 00:00:00 GMT"
      @res["Pragma"] = "no-cache"
      @res["Cache-Control"] = "no-cache, max-age=0, must-revalidate"
    end

    def hdr_cache_forever
      now = Time.now().to_i
      @res["Date"] = now.to_s
      @res["Expires"] = (now + 31536000).to_s;
      @res["Cache-Control"] = "public, max-age=31536000";
    end
  end
end
