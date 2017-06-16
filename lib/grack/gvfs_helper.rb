require 'json'
def parse_req(str)
    JSON.parse(str)
end

def get_obj_id_list(git, req)
    obj_id_list = []
    commit_id_list = []
    commit_depth = req["commitDepth"].to_i
    req["objectIds"].each do |obj_id|
        obj_type = git.execute(["cat-file","-t",obj_id])
        if obj_type=="commit"
            commit_id_list << obj_id
            commit_id_list << get_depth_commit(git,obj_id,commit_depth) if commit_depth>1
        else
            obj_id_list << obj_id
        end
    end
    commit_id_list.flatten!
    commit_id_list.each do |commit_id|
       obj_id_list << commit_id
       obj_id_list << get_tree_list(git, commit_id,"commit")
    end
    return obj_id_list
end

def get_depth_commit(git,commit_id, commit_depth)
    commit_list = git.execute(["rev-list","-#{commit_depth}",commit_id]).split("\n")
    (commit_list.length>1) ? commit_list[1..-1]: []
end

def get_tree_list(git, obj_id, type)    
    tree_list = []
    if type == "commit"
        tree_list << git.execute(["cat-file","-p",obj_id])[5..44]
        tree_list << get_tree_list(git, tree_list.last, "tree")
    else
        content = git.execute(["cat-file","-p",obj_id])
        content.split("\n").each do |line|
            if line[7..10]=="tree"
                tree_list << line[12..51]
                get_tree_list(git, tree_list.last, "tree")
            end
        end
    end
    return tree_list
end

def pack_file(git,obj_id_list)
    rnd = rand(100000)
    Dir.chdir(git.repo)
    `mkdir #{git.repo}/tmp` unless File.directory?(git.repo+"/tmp")
    cmd = "echo \"#{obj_id_list.flatten.join("\\n")}\" | git pack-objects tmp/pack-#{rnd}"
    `#{cmd}`
    file_name = `ls #{git.repo}/tmp/pack-#{rnd}-*.pack`
    file_name.strip.gsub(git.repo+"/","")
end

def get_obj_size(git,obj_list)
    sizes = []
    obj_list.each do |obj_id|
        sizes << {"Id": obj_id, "Size": git.execute(["cat-file", "-s", obj_id])}
    end
    return sizes
end

def get_packfile_list(git,lastPackTimestamp)
    Dir.chdir(git.repo)
    list = []
    packfile_list = `ls -t #{git.repo}/tmp/pack-*.pack`.split("\n")
    packfile_list.each do |file|
        list << file if File.stat(file).mtime.to_i>lastPackTimestamp
    end
    return list
end

def get_packed_objs(git,pack_list)
    Dir.chdir(git.repo)
    list = []
    pack_list.each do |file|
        info = git.execute ["verify-pack","-v",file]
        info.split("\n").each do |line|
            id,obj_type = line.split(" ")
            if obj_type=="commit" || obj_type=="tree"
                list << id
            end
        end
    end
    return list.uniq
end