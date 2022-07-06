# frozen_string_literal: true

RSpec.describe ComplexWorkflows do
  before(:each) { Redis.new.flushdb }

  describe '::Starter.perform' do
    it "enqueues step 1 into a workflow-specific batch within the parent batch" do
      workflow_class = create_workflow do
        step(:foo) {|a,b| }
      end

      workflow_starter_instance = Module.const_get("#{workflow_class}::Starter").new
      parent_batch = Sidekiq::Batch.new
      allow(workflow_starter_instance).to receive(:batch).and_return(parent_batch)

      workflow_starter_instance.perform(1,2)

      job = Sidekiq::Queue.new("default").first
      expect(job["class"]).to eql workflow_class.to_s
      expect(job["args"]).to eql [1,2]

      step_batch = Sidekiq::Batch.new(job["bid"])
      expect(step_batch.parent_bid).to eql(parent_batch.bid)
    end
  end

  describe "::Starter.sidekiq_options_hash" do
    it "inherits from the workflow class" do
      sidekiq_options = {"queue" => :so_urgent, "backtrace" => 5000, "retry" => 100}

      workflow_class = create_workflow(sidekiq_options: sidekiq_options) do
        step(:foo) {}
      end

      expect(workflow_class.sidekiq_options_hash).to eql(sidekiq_options)
    end
  end

  describe ".start" do
    it "creates a distinct batch for the workflow and puts a single job in it" do
      workflow_class = create_workflow do
        step(:foo) {}
      end
      workflow_batch = workflow_class.start

      job = Sidekiq::Queue.new("default").first
      expect(job["bid"]).to eql workflow_batch.bid
    end

    it "the initial job is an instance of the workflow" do
      workflow_class = create_workflow do
        step(:foo) {}
      end
      workflow_batch = workflow_class.start

      job = Sidekiq::Queue.new("default").first
      expect(job["class"]).to eql workflow_class.to_s
    end

    it "passes the arguments to the initial job" do
      workflow_class = create_workflow do
        step(:foo) {|*args| }
      end
      workflow_batch = workflow_class.start(1,2)

      job = Sidekiq::Queue.new("default").first
      expect(job["args"]).to eql [1,2]
    end

    it "makes args available in the description" do
      workflow_class = create_workflow do
        description do |a,b|
          @args.first
        end
        step(:foo) {|*args| }
      end

      expect(workflow_class.start("fancy description", {}).description).to eq("fancy description")
    end

    it "populates the callback queue on the workflow batch from the sidekiq_options setting" do
      queue_name = :urgent
      workflow_class = create_workflow(sidekiq_options: {queue: queue_name}) do
        step(:foo) {|a,b| }

        success do |a,b|
        end
      end

      workflow_batch = workflow_class.start(1,2)
      expect(workflow_batch.callback_queue).to eql(queue_name)
    end

    it "defines a success callback on the workflow batch, including args" do
      workflow_class = create_workflow do
        step(:foo) {|a,b| }

        success do |a,b|
        end
      end

      workflow_batch = workflow_class.start(1,2)
      expect(workflow_batch.callbacks["success"]).to eql(
        [{"#{workflow_class}#success"=>[1, 2]}]
      )
    end

    it "defines a death callback on the workflow batch, including args" do
      workflow_class = create_workflow do
        step(:foo) {|a,b| }

        death do |a,b|
        end
      end

      workflow_batch = workflow_class.start(1,2)
      expect(workflow_batch.callbacks["death"]).to eql(
        [{"#{workflow_class}#death"=>[1, 2]}]
      )
    end

    it "handles mutation of arguments per preprocess_args callback" do
      workflow_class = create_workflow do
        step(:foo) {|a,b| }

        preprocess_args do |a,b|
          [a*10, b*10]
        end

        success do |a,b|
        end
      end

      workflow_batch = workflow_class.start(1,2)

      job = Sidekiq::Queue.new("default").first
      expect(job["args"]).to eql [10,20]

      expect(workflow_batch.callbacks["success"]).to eql(
        [{"#{workflow_class}#success"=>[10, 20]}]
      )
    end

    it "preprocess_args callback has access to instance methods" do
      workflow_class = create_workflow do
        step(:foo) {|a, options| }

        preprocess_args do |a, options|
          [double(a), options]
        end

        success do |a, options|
        end

      end

      workflow_class.define_method(:double) do |x|
        x*2
      end

      workflow_batch = workflow_class.start(1, {})

      job = Sidekiq::Queue.new("default").first
      expect(job["args"]).to eql [2, {}]

      expect(workflow_batch.callbacks["success"]).to eql(
        [{"#{workflow_class}#success"=>[2,{}]}]
      )
    end
  end

  describe '#perform' do
    it "logic is defined based on the first step" do
      workflow_class = create_workflow do
        step(:foo) do
          raise "this code was called"
        end
      end

      expect{ workflow_class.new.perform }.to raise_error(RuntimeError).with_message("this code was called")
    end

    it "the logic receives arguments" do
      workflow_class = create_workflow do
        step(:foo) do |a,b|
          raise [a,b].inspect
        end
      end

      expect{ workflow_class.new.perform(1,2) }.to raise_error(RuntimeError).with_message([1,2].inspect)
    end

    it "makes args available in the description" do
      workflow_class = create_workflow do
        step(:foo) {|*args| }
        description do |a,b|
          raise @args.first
        end
      end

      expect{ workflow_class.new.perform("fancy description",2) }.to raise_error(RuntimeError).with_message("fancy description")
    end


    describe "#step_jobs" do
      it "creates a batch for the step inside the workflow" do
        workflow_class = create_workflow do
          step(:foo) do
            step_jobs do
              Job.perform_async
            end
          end
        end

        workflow_instance = workflow_class.new
        workflow_batch = Sidekiq::Batch.new
        allow(workflow_instance).to receive(:batch).and_return(workflow_batch)

        workflow_instance.perform

        step_batch = Sidekiq::BatchSet.new.first
        expect(step_batch.parent.bid).to eql workflow_batch.bid
      end

      it "creates a batch for the step that calls the next step on success" do
        workflow_class = create_workflow do
          step(:foo) do |a,b|
            step_jobs do
              Job.perform_async
            end
          end

          step(:bar) { }
        end

        workflow_instance = workflow_class.new
        workflow_batch = Sidekiq::Batch.new
        allow(workflow_instance).to receive(:batch).and_return(workflow_batch)

        workflow_instance.perform(1,2)

        step_batch = Sidekiq::BatchSet.new.first
        expect(step_batch.callbacks["success"]).to eql(
          [{"#{workflow_class}#bar"=>[1, 2]}]
        )
      end

      it "creates a batch for the step that calls the next step on success" do
        queue_name = :urgent
        workflow_class = create_workflow(sidekiq_options: {queue: queue_name}) do
          step(:foo) do |a,b|
            step_jobs do
              Job.perform_async
            end
          end

          step(:bar) { }
        end

        workflow_instance = workflow_class.new
        workflow_batch = Sidekiq::Batch.new
        allow(workflow_instance).to receive(:batch).and_return(workflow_batch)

        step_batch = workflow_instance.perform(1,2)

        expect(step_batch.callback_queue).to eql(queue_name)
      end

      it "errors if no jobs are enqueued" do
        workflow_class = create_workflow do
          step(:foo) do
            step_jobs do
              # no-op
            end
          end

          step(:bar) { }
        end

        workflow_instance = workflow_class.new
        workflow_batch = Sidekiq::Batch.new
        allow(workflow_instance).to receive(:batch).and_return(workflow_batch)

        expect{ workflow_instance.perform }.to raise_error ComplexWorkflows::NoJobsEnqueued
      end
    end

    describe "#workflow_jobs" do
      it "puts the jobs in the workflow, not in the step" do
        workflow_class = create_workflow do
          step(:step_1) do |a,b|
            workflow_jobs do
              Job.perform_async a, b
            end
          end
        end

        workflow_instance = workflow_class.new
        workflow_batch = Sidekiq::Batch.new
        allow(workflow_instance).to receive(:batch).and_return(workflow_batch)

        workflow_instance.perform(1,2)

        job = Sidekiq::Queue.new("default").to_a.first
        expect(job["bid"]).to eql workflow_batch.bid
        expect(job["args"]).to eql [1,2]
      end
    end

    describe "#parent_jobs"
  end

  describe "#second_step" do
    describe "#step_jobs" do
      it "receives the arguments as expected" do
        workflow_class = create_workflow do
          step(:step_1) { }

          step(:step_2) do |a,b|
            raise [a,b].inspect
          end
        end

        workflow_instance = workflow_class.new
        workflow_batch = Sidekiq::Batch.new
        # need to put a job in the batch to get it to save to sidekiq
        workflow_batch.jobs do
          Job.perform_async
        end
        status = double(:status, parent_bid: workflow_batch.bid)

        expect{ workflow_instance.step_2(status, [1,2]) }.to raise_error(RuntimeError).with_message([1,2].inspect)
      end

      it "creates a batch for step_2 that calls the next step on success" do
        workflow_class = create_workflow do
          step(:step_1) { }

          step(:step_2) do |a,b|
            step_jobs do
              Job.perform_async
            end
          end

          step(:step_3)
        end

        workflow_instance = workflow_class.new
        workflow_batch = Sidekiq::Batch.new
        # need to put a job in the batch to get it to save to sidekiq
        workflow_batch.jobs do
          Job.perform_async
        end
        status = double(:status, parent_bid: workflow_batch.bid)

        workflow_instance.step_2(status, [1,2])

        step_2_batch = Sidekiq::BatchSet.new.to_a.last
        expect(step_2_batch.callbacks["success"]).to eql(
          [{"#{workflow_class}#step_3"=>[1, 2]}]
        )
      end
    end

    describe "#workflow_jobs" do
      it "puts the jobs in the workflow, not in the step" do
        workflow_class = create_workflow do
          step(:step_1) { }

          step(:step_2) do |a,b|
            workflow_jobs do
              Job.perform_async a, b
            end
          end
        end

        workflow_instance = workflow_class.new
        workflow_batch = Sidekiq::Batch.new
        # need to put a job in the batch to get it to save to sidekiq
        workflow_batch.jobs do
          Job.perform_async
        end
        status = double(:status, parent_bid: workflow_batch.bid)

        workflow_instance.step_2(status, [1,2])

        job = Sidekiq::Queue.new("default").to_a.first
        expect(job["bid"]).to eql workflow_batch.bid
        expect(job["args"]).to eql [1,2]
      end
    end

    describe "#parent_jobs"
  end

  describe "#success" do
    it "receives the arguments as expected" do
      workflow_class = create_workflow do
        step(:step_1) { }

        success do |a,b|
          raise [a,b].inspect
        end
      end

      status = double(:status, parent_bid: nil)
      expect{ workflow_class.new.success(status, [1,2]) }.to raise_error(RuntimeError).with_message([1,2].inspect)
    end

    describe "#step_jobs" # raise error if called?
    describe "#workflow_jobs" # raise error if called?

    describe "#parent_jobs" do
      it "puts the job in the parent batch" do
        workflow_class = create_workflow do
          step(:step_1) { }

          success do |a,b|
            parent_jobs do
              Job.perform_async(a,b)
            end
          end
        end

        job = workflow_class.new
        parent_batch = Sidekiq::Batch.new
        # need to put a job in the batch to get it to save to sidekiq
        parent_batch.jobs do
          Job.perform_async
        end
        status = double(:status, parent_bid: parent_batch.bid)

        job.success(status, [1,2])

        job = Sidekiq::Queue.new("default").to_a.first
        expect(job["bid"]).to eql parent_batch.bid
        expect(job["args"]).to eql [1,2]
      end
    end
  end
end
