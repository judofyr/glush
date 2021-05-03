require_relative 'helper'

class TestPartitionRefinement < Minitest::Spec
  let(:pr) { Glush::PartitionRefinement.new }

  it "can start from nothing" do
    pr.observe([1, 2, 3])
    assert_equal [Set[1, 2, 3]], pr.partition_elements
  end

  it "can refine" do
    pr.observe([1, 2, 3, 4])
    pr.observe([1, 2])
    pr.observe([3, 4])
    assert_equal [[1, 2], [3, 4]], pr.partition_elements.map(&:to_a).sort
  end
end
