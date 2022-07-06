class ComplexWorkflows::Workflow
  attr_reader :steps
  def initialize(&blk)
    @steps = []
    @callbacks = {}
    @description_callback ||= Proc.new do |args|
      "#{self.class} (#{args})"
    end
    instance_eval(&blk)
  end

  def description(&blk)
    @description_callback = blk
  end

  def preprocess_args(&blk)
    @preprocess_args_callback = blk
  end

  def step(identifier, &blk)
    @steps << ComplexWorkflows::Step.new(identifier: identifier, block: blk)
  end

  %i(success complete death).each do |callback_type|
    define_method callback_type do |&blk|
      @callbacks[callback_type] = blk
    end
  end

  def register(base_class)
    define_starter_job_class(base_class)
    define_start_method(base_class)
    define_perform_method(base_class)
    define_step_callbacks(base_class) if steps.present?
    define_callbacks(base_class) if @callbacks
  end

  private

  def define_starter_job_class(base_class)
    klass = Class.new do
      include Sidekiq::Worker
      sidekiq_options base_class.sidekiq_options if base_class.sidekiq_options
    end

    klass.define_method :perform do |*args|
      batch.jobs do
        base_class.start(*args)
      end
    end

    base_class.const_set :Starter, klass
  end

  def define_start_method(base_class)
    preprocess_args_callback = @preprocess_args_callback
    description_callback = @description_callback
    callbacks = @callbacks

    base_class.define_method :start do |*args|
      workflow_batch = Sidekiq::Batch.new
      workflow_batch.callback_queue = base_class.sidekiq_options["queue"]

      @args = args
      if preprocess_args_callback
        @args = instance_exec(*args, &preprocess_args_callback)
      end

      if description_callback
        workflow_batch.description = instance_exec(*@args, &description_callback)
      end

      callbacks.keys.each do |callback_type|
        workflow_batch.on(callback_type, "#{base_class.name}##{callback_type}", @args)
      end

      workflow_batch.jobs do
        base_class.perform_async(*@args)
      end

      workflow_batch
    end
  end

  def define_perform_method(base_class)
    raise "must have steps" if @steps.empty?
    steps = @steps
    step = steps.shift
    description_callback = @description_callback

    base_class.define_method(:perform) do |*args|
      @workflow_batch = batch
      @parent_batch = Sidekiq::Batch.new(@workflow_batch.parent_bid) if @workflow_batch&.parent_bid

      @args = args

      if description_callback
        @description = "#{instance_exec(*args, &description_callback)}: #{step.identifier}"
      end

      @next_step = steps.first if steps.present?

      instance_exec(*args, &step.block)

      return @step_batch
    ensure
      @parent_batch = nil
      @workflow_batch = nil
      @step_batch = nil
    end
  end

  def define_step_callbacks(base_class)
    description_callback = @description_callback

    (steps + [nil]).each_cons(2) do |step, next_step|
      base_class.define_method step.identifier do |status, args|
        @workflow_batch = Sidekiq::Batch.new(status.parent_bid)

        @parent_batch = Sidekiq::Batch.new(@workflow_batch.parent_bid) if @workflow_batch.parent_bid
        @args = args

        if description_callback
          @description = "#{instance_exec(*args, &description_callback)}: #{step.identifier}"
        end

        @next_step = next_step

        instance_exec(*args, &step.block)

        return @step_batch
      ensure
        @parent_batch = nil
        @workflow_batch = nil
        @step_batch = nil
      end
    end
  end

  def define_callbacks(base_class)
    @callbacks.each do |callback, callback_blk|
      base_class.define_method callback do |status, args|
        @parent_batch = Sidekiq::Batch.new(status.parent_bid) if status.parent_bid
        @args = args
        instance_exec(*args, &callback_blk)
      ensure
        @parent_batch = nil
      end
    end
  end
end
