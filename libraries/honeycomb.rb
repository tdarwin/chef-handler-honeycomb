require "chef/http/simple_json"
require "time"
require "securerandom" unless defined?(SecureRandom)

VERSION="3.0.2"

class Honeycomb
  class << self
    attr_accessor :converge_start,
                  :converge_duration,
                  :handlers_start,
                  :handlers_duration,
                  :num_resources_modified

    def num_resources_modified
      @num_resources_modified ||= 0
    end

    def converge_started
      self.converge_start = Time.now
    end

    def converge_completed
      if converge_start
        self.converge_duration = Time.now - converge_start
      end
    end

    def handlers_started
      self.handlers_start = Time.now
    end

    def handlers_completed
      if handlers_start
        self.handlers_duration = Time.now - handlers_start
      end
    end

    def resource_update_applied
      self.num_resources_modified += 1
    end

    def merge_hash(hash_src, hash_dest)
      ::Chef::Mixin::DeepMerge.deep_merge!(hash_src, hash_dest)
    end

    def generate_span(run_status, **args)
      run_id = run_status.methods.include?(:run_id) ? run_status.run_id : nil
      node_exists = run_status.methods.include?(:node) ? true : false
      #########################################
      # These values go in every span
      #########################################
      span_data = {
        'trace.trace_id' => args[:trace_id],
        'trace.span_id' => args[:span_id],
        'trace.parent_id' => args[:parent_id] ||= nil,
        'service.name' => 'chef',
        'name' => args[:event] ||= 'chef-client',
        'run_id' => run_id,
        'chef_resources_udpated' => num_resources_modified,
      }

      config_data = {
        'chef.config.server' => Chef::Config[:chef_server_url],
        'chef.config.fips' => Chef::Config[:fips],
        'chef.config.data_collector.server_url' => Chef::Config[:data_collector][:server_url],
        'chef.config.http_proxy' => Chef::Config[:http_proxy],
        'chef.config.https_proxy' => Chef::Config[:https_proxy],
        'chef.config.ftp_proxy' => Chef::Config[:ftp_proxy],
        'chef.config.no_proxy' => Chef::Config[:no_proxy],
        'chef.config.rubygems_url' => Chef::Config[:rubygems_url],
        'chef.config.policy_name' => Chef::Config[:policy_name],
        'chef.config.policy_group' => Chef::Config[:policy_grid],
        'chef.config.named_run_list' => Chef::Config[:named_run_list],
      }
      merge_hash(config_data, span_data)

      resource_data = {
        'chef.resource_name' => args[:resource_name],
        'chef.resource_type' => args[:resource_type],
        'chef.recipe' => args[:recipe],
        'chef.cookbook' => args[:cookbook],
        'chef.resource_action' => args[:resource_action],
        'chef.resource_status' => args[:resource_status],
      }
      merge_hash(resource_data, span_data)

      if node_exists == true
        node_data = {
          'chef.node.name' => run_status.node.name,
          'chef.node.guid' => run_status.node['chef_guid'],
          'chef.node.chef_version' => run_status.node['chef_packages']['chef']['version'],
          'chef.node.ohai_version' => run_status.node['chef_packages']['ohai']['version'],
          'chef.node.os' => run_status.node['os'],
          'chef.node.os.version' => run_status.node['os_version'],
          'chef.node.platform' => run_status.node['platform'],
          'chef.node.platform_family' => run_status.node['platform_family'],
          'chef.node.platform_version' => run_status.node['platform_version'],
          'chef.node.kernel.processor' => run_status.node['kernel']['processor'],
          'chef.node.ipaddress' => run_status.node['ipaddress'],
          'chef.node.hostname' => run_status.node['hostname'],
          'chef.node.machinename' => run_status.node['machinename'],
          'chef.node.fqdn' => run_status.node['fqdn'],
          'chef.node.cloud' => run_status.node['cloud'],
          'chef.environment' => run_status.node['chef_environment'],
          'chef.policy_name' => run_status.node['policy_name'],
          'chef.policy_group' => run_status.node['policy_group'],
          'chef.policy_revision' => run_status.node['policy_revision'],
          'chef.run_list' => run_status.node.run_list.to_s,
          'chef.roles' => run_status.node['roles'],
        }

        merge_hash(node_data, span_data)

        node_attributes = run_status.node['honeycomb']['tracked_attributes']
        merge_hash(node_attributes, span_data)
      end

      #########################################
      # Define the parent_id if not the root span
      #########################################
      if args.key?(:parent_id)
        span_data['meta.span_type'] = 'child'
      else
        span_data['meta.span_type'] = 'root'
      end

      #########################################
      # Span Duration Values
      #########################################
      if args.key?(:duration_ms)
        timing_data = {
          'duration_ms' => args[:duration_ms],
          'start_time'  => args[:start_time],
          'end_time'    => args[:end_time],
        }
        merge_hash(timing_data, span_data)
      end

      #########################################
      # These values are used by the root span
      #########################################
      if args[:end_run] == true
        end_run_data = {
          'start_time' => run_status.start_time.iso8601(fraction_digits = 3),
          'end_time' => run_status.end_time.iso8601(fraction_digits = 3),
          'duration_ms' => (run_status.elapsed_time * 1000.0),
          'success' => run_status.success?,
        }

        merge_hash(end_run_data, span_data)

        #########################################
        # If run fails, make it a failure
        #########################################
        unless run_status.success? || args[:error] == false
          run_backtrace = nil
          run_backtrace = run_status.backtrace.join("\n") unless run_status.backtrace.nil?

          error_data = {
            "error" => true,
            "exception" => run_status.exception,
            "backtrace" => run_backtrace,
          }

          merge_hash(error_data, span_data)
        end

        #########################################
        # If sending to Automate, generate link to client run
        #########################################
        unless run_status.node['honeycomb']['automate_fqdn'].nil?
          automate_run_url = "https://#{run_status.node['honeycomb']['automate_fqdn']}"
          automate_run_url += "/infrastructure/client-runs/#{run_status.node['chef_guid']}"
          automate_run_url += "/runs/#{run_status.run_id}"
          
          automate_data = {
            'chef.automate_run_link' => automate_run_url,
          }

          merge_hash(automate_data, span_data)
        end
      end

      #########################################
      # Return the completed span data
      #########################################
      return_data = Hash.new
      return_data['time'] = args[:start_time] ||= run_status.start_time.iso8601(fraction_digits = 3)
      return_data['data'] = span_data
      return_data
    end

    def report(run_status, trace_batch)
      
      url = run_status.node['honeycomb']['api_url']
      path = "/1/batch/#{run_status.node['honeycomb']['dataset']}"
      headers = {
        "X-Honeycomb-Team" => run_status.node['honeycomb']['writekey'],
        "user-agent" => "honeycomb-chef-handler/#{VERSION}",
      }

      Chef::Log.info "Sending trace to Honeycomb API at #{url}#{path}"
      Chef::HTTP::SimpleJSON.new(url).post(path, trace_batch, headers)
    end
  end
end
