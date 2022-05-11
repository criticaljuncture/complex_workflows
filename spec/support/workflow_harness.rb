require "sidekiq_workflows"

def workflow(*args, &blk)
  block = blk
  klass = Class.new do
    include SidekiqWorkflows

    workflow(&block)
  end

  Module.const_set("Workflow#{rand(10000)}", klass)

  klass.start(*args)
end