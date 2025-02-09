###############################################################
# Adding this recipe to the runlist of your node or policyfile
#   should work well to get you nice waterfall representations
#   of your Chef-Client runs in Honeycomb
###############################################################

Chef.event_handler do
  trace_id = SecureRandom.hex(16)
  root_span_id = SecureRandom.hex(8)
  compile_span_id = SecureRandom.hex(8)
  converge_span_id = SecureRandom.hex(8)
  trace_batch = []
  comp_start = Time.parse(Time.now.iso8601(fraction_digits = 3))
  @conv_start = Time.parse(Time.now.iso8601(fraction_digits = 3))
  @current_cookbook_name = nil
  @current_recipe_name = nil
  @converge_phase = false

  ## Requires later version of Chef to run
  on :cookbook_compilation_complete do
    |run_context|
    @comp_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))
  end
  on :converge_start do
    |run_context|
    @comp_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))
    @conv_start_run_context = run_context
    @conv_start = Time.parse(Time.now.iso8601(fraction_digits = 3))
    @current_cookbook_name = nil
    @current_recipe_name = nil
    @converge_phase = true
  end

  on :converge_complete do
    recipe_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))

    duration = recipe_stop - @recipe_start
    duration_ms = duration * 1000
    recipe_span = ::Honeycomb.generate_span(
      @conv_start_run_context,
      trace_id: trace_id,
      span_id: @current_recipe_span,
      parent_id: @current_cookbook_span,
      duration_ms: duration_ms,
      start_time: @recipe_start.iso8601(fraction_digits = 3),
      end_time: recipe_stop.iso8601(fraction_digits = 3),
      event: "recipe: #{@current_recipe_name}",
    )

    trace_batch << recipe_span

    cookbook_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))

    duration = cookbook_stop - @cookbook_start
    duration_ms = duration * 1000

    cookbook_span = ::Honeycomb.generate_span(
      @conv_start_run_context,
      trace_id: trace_id,
      span_id: @current_cookbook_span,
      parent_id: converge_span_id,
      duration_ms: duration_ms,
      start_time: @cookbook_start.iso8601(fraction_digits = 3),
      end_time: cookbook_stop.iso8601(fraction_digits = 3),
      event: "cookbook: #{@current_cookbook_name}",
    )

    trace_batch << cookbook_span

    @conv_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))
    conv_duration = @conv_stop - @conv_start
    conv_duration_ms = conv_duration * 1000
    converge_span = ::Honeycomb.generate_span(
      @conv_start_run_context,
      trace_id: trace_id,
      span_id: converge_span_id,
      parent_id: root_span_id,
      duration_ms: conv_duration_ms,
      start_time: @conv_start.iso8601(fraction_digits = 3),
      end_time: @conv_stop.iso8601(fraction_digits = 3),
      event: 'converge',
    )
    trace_batch << converge_span
  end

  on :converge_failed do
    |exception|
    recipe_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))

    recipe_start_time = @recipe_start

    duration = recipe_stop - recipe_start_time
    duration_ms = duration * 1000
    recipe_span = ::Honeycomb.generate_span(
      @conv_start_run_context,
      trace_id: trace_id,
      span_id: @current_recipe_span,
      parent_id: @current_cookbook_span,
      duration_ms: duration_ms,
      start_time: @recipe_start.iso8601(fraction_digits = 3),
      end_time: recipe_stop.iso8601(fraction_digits = 3),
      event: "recipe: #{@current_recipe_name}",
      error: true,
      exception: exception,
    )

    trace_batch << recipe_span

    cookbook_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))

    duration = cookbook_stop - @cookbook_start
    duration_ms = duration * 1000
    cookbook_span = ::Honeycomb.generate_span(
      @conv_start_run_context,
      trace_id: trace_id,
      span_id: @current_cookbook_span,
      parent_id: converge_span_id,
      duration_ms: duration_ms,
      start_time: @cookbook_start.iso8601(fraction_digits = 3),
      end_time: cookbook_stop.iso8601(fraction_digits = 3),
      event: "cookbook: #{@current_cookbook_name}",
      error: true,
      exception: exception,
    )

    trace_batch << cookbook_span

    @conv_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))
    conv_duration = @conv_stop - @conv_start
    conv_duration_ms = conv_duration * 1000

    converge_span = ::Honeycomb.generate_span(
      @conv_start_run_context,
      trace_id: trace_id,
      span_id: converge_span_id,
      parent_id: root_span_id,
      duration_ms: conv_duration_ms,
      start_time: @conv_start.iso8601(fraction_digits = 3),
      end_time: @conv_stop.iso8601(fraction_digits = 3),
      error: true,
      exception: exception,
      event: 'converge',
    )
    trace_batch << converge_span
  end

  on :resource_skipped do
    @resource_status = 'skipped'
  end
  on :resource_updated do
    @resource_status = 'updated'
  end
  on :resource_up_to_date do
    @resource_status = 'up to date'
  end
  on :resource_failed do
    @resource_status = 'failed'
  end
  on :resource_completed do
    |resource|
    resource_stop = Time.parse(Time.now.iso8601(fraction_digits = 3))
    duration_ms = resource.elapsed_time * 1000
    resource_start = resource_stop - resource.elapsed_time

    unless @converge_phase == false
      if @current_recipe_name.nil?
        @recipe_start = @conv_start
        @current_recipe_name = resource.recipe_name
        @current_recipe_span = SecureRandom.hex(8)
      end

      unless resource.recipe_name.nil?
        if @current_recipe_name != resource.recipe_name
          recipe_stop = Time.parse(resource_start.iso8601(fraction_digits = 3))

          recipe_start_time = @recipe_start.nil? ? recipe_stop - resource.elapsed_time : @recipe_start

          duration = recipe_stop - recipe_start_time
          duration_ms = duration * 1000
          recipe_span = ::Honeycomb.generate_span(
            resource,
            trace_id: trace_id,
            span_id: @current_recipe_span,
            parent_id: @current_cookbook_span,
            duration_ms: duration_ms,
            start_time: recipe_start_time.iso8601(fraction_digits = 3),
            end_time: recipe_stop.iso8601(fraction_digits = 3),
            event: "recipe: #{@current_recipe_name}",
          )

          trace_batch << recipe_span

          @recipe_start = recipe_stop
          @current_recipe_name = resource.recipe_name
          @current_recipe_span = SecureRandom.hex(8)
        end
      end

      if @current_cookbook_name.nil?
        @cookbook_start = @conv_start
        @current_cookbook_name = resource.cookbook_name
        @current_cookbook_span = SecureRandom.hex(8)
      end

      unless resource.cookbook_name.nil?
        if @current_cookbook_name != resource.cookbook_name
          cookbook_stop = Time.parse(resource_start.iso8601(fraction_digits = 3))

          cookbook_start_time = @cookbook_start.nil? ? cookbook_stop - resource.elapsed_time : @cookbook_start

          duration = cookbook_stop - cookbook_start_time
          duration_ms = duration * 1000
          cookbook_span = ::Honeycomb.generate_span(
            resource,
            trace_id: trace_id,
            span_id: @current_cookbook_span,
            parent_id: converge_span_id,
            duration_ms: duration_ms,
            start_time: cookbook_start_time.iso8601(fraction_digits = 3),
            end_time: cookbook_stop.iso8601(fraction_digits = 3),
            event: "cookbook: #{@current_cookbook_name}",
          )

          trace_batch << cookbook_span

          @cookbook_start = cookbook_stop
          @current_cookbook_name = resource.cookbook_name
          @current_cookbook_span = SecureRandom.hex(8)
        end
      end
    end

    if @resource_status.nil?
      if resource.updated?
        @resource_status = 'updated'
        ::Honeycomb.resource_update_applied()
      else
        @resource_status = 'not-updated'
      end
    end

    resource_parent_span = @converge_phase ? @current_recipe_span : compile_span_id

    resource_type = resource.to_s.gsub(/\[.*\]$/, '')
    resource_span = ::Honeycomb.generate_span(
      resource,
      trace_id: trace_id,
      span_id: SecureRandom.hex(8),
      parent_id: resource_parent_span,
      duration_ms: resource.elapsed_time * 1000,
      start_time: resource_start.iso8601(fraction_digits =3),
      end_time: resource_stop.iso8601(fraction_digits = 3),
      resource_name: resource.to_s,
      resource_type: resource_type,
      recipe: resource.recipe_name,
      cookbook: resource.cookbook_name,
      resource_action: resource.action,
      resource_status: @resource_status,
      event: resource.to_s,
    )
    trace_batch << resource_span
  end

  Chef::Client.when_run_completes_successfully {|run_status| @handler.instance_variable_set(:@run_status, run_status) }
  Chef::Client.when_run_fails {|run_status| @handler.instance_variable_set(:@run_status, run_status) }
  on :run_completed do
    root_trace = ::Honeycomb.generate_span(
      @run_status,
      trace_id: trace_id,
      span_id: root_span_id,
      end_run: true
    )
    trace_batch << root_trace

    comp_duration = @comp_stop - (Time.parse(@run_status.start_time.iso8601(fraction_digits = 3)))
    comp_duration_ms = comp_duration * 1000
    compile_span = ::Honeycomb.generate_span(
      @run_status,
      trace_id: trace_id,
      span_id: compile_span_id,
      parent_id: root_span_id,
      duration_ms: comp_duration_ms,
      start_time: @run_status.start_time.iso8601(fraction_digits = 3),
      end_time: @comp_stop.iso8601(fraction_digits = 3),
      event: 'compile',
    )
    trace_batch << compile_span

    handler_start = @conv_stop
    handler_stop = Time.parse(@run_status.end_time.iso8601(fraction_digits = 3))
    handler_duration = handler_stop - handler_start
    handler_duration_ms = handler_duration * 1000
    handler_span = ::Honeycomb.generate_span(
      @run_status,
      trace_id: trace_id,
      span_id: SecureRandom.hex(8),
      parent_id: root_span_id,
      duration_ms: handler_duration_ms,
      start_time: handler_start.iso8601(fraction_digits = 3),
      end_time: handler_stop.iso8601(fraction_digits = 3),
      event: 'running-handlers'
    )
    trace_batch << handler_span

    ::Honeycomb.report(@run_status, trace_batch)
  end
  on :run_failed do
    root_trace = ::Honeycomb.generate_span(@run_status, trace_id: trace_id, span_id: root_span_id, end_run: true)
    trace_batch << root_trace

    comp_duration = @comp_stop - (Time.parse(@run_status.start_time.iso8601(fraction_digits =3)))
    comp_duration_ms = comp_duration * 1000
    compile_span = ::Honeycomb.generate_span(
      @run_status,
      trace_id: trace_id,
      span_id: compile_span_id,
      parent_id: root_span_id,
      duration_ms: comp_duration_ms,
      start_time: @run_status.start_time.iso8601(fraction_digits = 3),
      end_time: @comp_stop.iso8601(fraction_digits = 3),
      event: 'compile',
    )
    trace_batch << compile_span

    handler_start = @conv_stop
    handler_stop = Time.parse(@run_status.end_time.iso8601(fraction_digits = 3))
    handler_duration = handler_stop - handler_start
    handler_duration_ms = handler_duration * 1000
    handler_span = ::Honeycomb.generate_span(
      @run_status,
      trace_id: trace_id,
      span_id: SecureRandom.hex(8),
      parent_id: root_span_id,
      duration_ms: handler_duration_ms,
      start_time: handler_start.iso8601(fraction_digits = 3),
      end_time: handler_stop.iso8601(fraction_digits = 3),
      event: "running-handlers"
    )
    trace_batch << handler_span

    ::Honeycomb.report(@run_status, trace_batch)
  end
end

  # By the time this recipe has been processed,
  # these handlers have already been triggered
  # so you can't add handlers anymore.
  # Copy and paste this section into your client.rb
  # or /etc/chef/client.d or /etc/chef/solo.d
  # depending on how you're running chef to get
  # them loaded early enough to get triggered
  #
  # Chef.event_handler do
  #   on :converge_start do
  #     ::Honeycomb.converge_start()
  #   end
  #   on :converge_complete do
  #     ::Honeycomb.converge_completed()
  #   end
  #   on :handlers_start do
  #     ::Honeycomb.handlers_start()
  #   end
  #   on :handlers_completed do
  #     ::Honeycomb.handlers_completed()
  #   end
  #   on :resource_update_applied do
  #     ::Honeycomb.resource_update_applied()
  #   end
  # end

