require 'pp'

# Monkey patching array with a in_groups_of method
# that walks an array in groups, pass a block to
# call the block on each sub array
class Array
    def in_groups_of(chunk_size, padded_with=nil)
        arr = self.clone

        # how many to add
        padding = chunk_size - (arr.size % chunk_size)

        # pad at the end
        arr.concat([padded_with] * padding)

        # how many chunks we'll make
        count = arr.size / chunk_size

        # make that many arrays
        result = []
        count.times {|s| result <<  arr[s * chunk_size, chunk_size]}

        if block_given?
            result.each{|a| yield(a)}
        else
            result
        end
    end
end

class MCollective::Application::Inventory<MCollective::Application
    description "Shows an inventory for a given node"

    option :script,
        :description    => "Script to run",
        :arguments      => ["--script SCRIPT"]

    def post_option_parser(configuration)
        configuration[:node] = ARGV.shift if ARGV.size > 0
    end

    def validate_configuration(configuration)
        unless configuration.include?(:node) || configuration.include?(:script)
            raise "Need to specify either a node name or a script to run"
        end
    end

    def node_inventory
        node = configuration[:node]

        util = rpcclient("rpcutil", :options => options)
        util.identity_filter node
        util.progress = false

        nodestats = util.custom_request("daemon_stats", {}, node, {"identity" => node})

        util.custom_request("inventory", {}, node, {"identity" => node}).each do |resp|
            puts "Inventory for #{resp[:sender]}:"
            puts

            if nodestats.is_a?(Array)
                nodestats = nodestats.first[:data]

                puts "   Server Statistics:"
                puts "                      Version: #{nodestats[:version]}"
                puts "                   Start Time: #{Time.at(nodestats[:starttime])}"
                puts "                  Config File: #{nodestats[:configfile]}"
                puts "                   Process ID: #{nodestats[:pid]}"
                puts "               Total Messages: #{nodestats[:total]}"
                puts "      Messages Passed Filters: #{nodestats[:passed]}"
                puts "            Messages Filtered: #{nodestats[:filtered]}"
                puts "                 Replies Sent: #{nodestats[:replies]}"
                puts "         Total Processor Time: #{nodestats[:times][:utime]} seconds"
                puts "                  System Time: #{nodestats[:times][:stime]} seconds"

                puts
            end

            puts "   Agents:"
            resp[:data][:agents].sort.in_groups_of(3, "") do |agents|
                puts "      %-15s %-15s %-15s" % agents
            end
            puts

            puts "   Configuration Management Classes:"
            resp[:data][:classes].sort.in_groups_of(2, "") do |klasses|
                puts "      %-30s %-30s" % klasses
            end
            puts

            puts "   Facts:"
            resp[:data][:facts].sort_by{|f| f[0]}.each do |f|
                puts "      #{f[0]} => #{f[1]}"
            end

            break
        end
    end

    # Helpers to create a simple DSL for scriptlets
    def format(fmt)
        @fmt = fmt
    end

    def fields(&blk)
        @flds = blk
    end

    def identity
        @node[:identity]
    end

    def facts
        @node[:facts]
    end

    def classes
        @node[:classes]
    end

    def agents
        @node[:agents]
    end

    def page_length(len)
        @page_length = len
    end

    def page_heading(fmt)
        @page_heading = fmt
    end

    def page_body(fmt)
        @page_body = fmt
    end

    # Expects a simple printf style format and apply it to
    # each node:
    #
    #    inventory do
    #        format "%s:\t\t%s\t\t%s"
    #
    #        fields { [ identity, facts["serialnumber"], facts["productname"] ] }
    #    end
    def inventory(&blk)
        raise "Need to give a block to inventory" unless block_given?

        blk.call if block_given?

        raise "Need to define a format" if @fmt.nil?
        raise "Need to define inventory fields" if @flds.nil?

        util = rpcclient("rpcutil", :options => @options)
        util.progress = false

        util.inventory do |t, resp|
            @node = {:identity => resp[:sender],
                     :facts    => resp[:data][:facts],
                     :classes  => resp[:data][:classes],
                     :agents   => resp[:data][:agents]}

            puts @fmt % @flds.call
        end
    end

    # Use the ruby formatr gem to build reports using Perls formats
    #
    # It is kind of ugly but brings a lot of flexibility in report
    # writing without building an entire reporting language.
    #
    # You need to have formatr installed to enable reports like:
    #
    #    formatted_inventory do
    #        page_length 20
    #
    #        page_heading <<TOP
    #
    #                Node Report @<<<<<<<<<<<<<<<<<<<<<<<<<
    #                            time
    #
    #    Hostname:         Customer:     Distribution:
    #    -------------------------------------------------------------------------
    #    TOP
    #
    #        page_body <<BODY
    #
    #    @<<<<<<<<<<<<<<<< @<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    #    identity,    facts["customer"], facts["lsbdistdescription"]
    #                                    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    #                                    facts["processor0"]
    #    BODY
    #    end
    def formatted_inventory(&blk)
        require 'formatr'

        raise "Need to give a block to formatted_inventory" unless block_given?

        blk.call if block_given?

        raise "Need to define page body format" if @page_body.nil?

        body_fmt = FormatR::Format.new(@page_heading, @page_body)
        body_fmt.setPageLength(@page_length)
        time = Time.now

        util = rpcclient("rpcutil", :options => @options)
        util.progress = false

        util.inventory do |t, resp|
            @node = {:identity => resp[:sender],
                     :facts    => resp[:data][:facts],
                     :classes  => resp[:data][:classes],
                     :agents   => resp[:data][:agents]}

            body_fmt.printFormat(binding)
        end
    rescue Exception => e
        STDERR.puts "Could not create report: #{e.class}: #{e}"
        exit 1
    end

    @fmt = nil
    @flds = nil
    @page_heading = nil
    @page_body = nil
    @page_length = 40

    def main
        if configuration[:script]
            if File.exist?(configuration[:script])
                eval(File.read(configuration[:script]))
            else
                raise "Could not find script to run: #{configuration[:script]}"
            end
        else
            node_inventory
        end
    end
end
