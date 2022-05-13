def create_workflow(sidekiq_options: nil, &blk)
  block = blk
  sidekiq_opts = sidekiq_options
  klass = Class.new do
    include SidekiqWorkflows
    sidekiq_options sidekiq_opts if sidekiq_opts

    workflow(&block)
  end

  Module.const_set("Workflow#{rand(100000)}", klass)
end