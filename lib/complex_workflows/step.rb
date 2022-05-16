class ComplexWorkflows::Step
  attr_reader :identifier, :block
  def initialize(identifier:, block:)
    @identifier = identifier
    @block = block
  end
end