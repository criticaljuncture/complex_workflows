class SidekiqWorkflow::Workflow
  attr_reader :steps
  def initialize(&blk)
    @steps = []
    instance_eval(&blk)
  end

  def description(&blk)
    @description_callback = blk
  end

  def step(identifier, &blk)
    @steps << SidekiqWorkflow::Step.new(identifier: identifier, block: blk)
  end

  def success(&blk)
    @success_callback = blk
  end

  def register(base_class)
    define_start_method(base_class)
    define_perform_method(base_class)
    define_step_callbacks(base_class) if steps.present?
    define_success_callback(base_class) if @success_callback
  end

  private

  def define_start_method(base_class)
    description_callback = @description_callback
    success_callback = @success_callback

    base_class.define_singleton_method :start do |*args|
      workflow_batch = Sidekiq::Batch.new
      
      if description_callback
        workflow_batch.description = instance_exec(*args, &description_callback)
      end

      # puts Rainbow("creating workflow batch: #{workflow_batch.bid}")
      
      workflow_batch.on(:success, "#{base_class.name}#success", args) if success_callback
      workflow_batch.jobs do
        base_class.perform_async(*args)
      end
    end
  end
  
  def define_perform_method(base_class)
    raise "must have steps" if @steps.empty?
    steps = @steps
    step = steps.shift
    description_callback = @description_callback

    base_class.define_method(:perform) do |*args|
      @workflow_batch = batch
      @parent_batch = Sidekiq::Batch.new(@workflow_batch.parent_bid) if @workflow_batch.parent_bid

      if description_callback
        @description = "#{instance_exec(*args, &description_callback)}: #{step.identifier}"
      end

      @next_step = steps.first if steps.present?
      @args = args

      instance_exec(*args, &step.block)
    ensure
      @parent_batch = nil
      @workflow_batch = nil
      @step_batch = nil
    end
  end

  def define_step_callbacks(base_class)
    description_callback = @description_callback

    (steps+[nil]).each_cons(2) do |step, next_step|
      base_class.define_method step.identifier do |status, args|
        @workflow_batch = Sidekiq::Batch.new(status.parent_bid)

        @parent_batch = Sidekiq::Batch.new(@workflow_batch.parent_bid) if @workflow_batch.parent_bid

        if description_callback
          @description = "#{instance_exec(*args, &description_callback)}: #{step.identifier}"
        end

        @next_step = next_step
        @args = args

        instance_exec(*args, &step.block)
      ensure
        @parent_batch = nil
        @workflow_batch = nil
        @step_batch = nil
      end
    end  
  end

  def define_success_callback(base_class)
    success_callback = @success_callback

    base_class.define_method :success do |status, args|
      @parent_batch = Sidekiq::Batch.new(status.parent_bid) if status.parent_bid
      instance_exec(*args, &success_callback)
    ensure
      @parent_batch = nil
    end
  end
end