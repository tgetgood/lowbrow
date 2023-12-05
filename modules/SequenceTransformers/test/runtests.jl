using SequenceTransformers
import SequenceTransformers as st

using Test


@testset "transforms" begin
  m = st.map(x -> x + 1)

  # Straight map
  @test collect(m(1:5)) == 2:6

  f = st.filter(x -> x % 2 === 0)

  # Fewer out than in
  @test collect(f(1:5)) == [2, 4]

  # More out than in
  @test collect(st.flatten(([1,2,3], [4,5,6]))) == 1:6

  # composition
  @test collect((f ∘ m)(1:5)) == [2,4,6]
end


m = st.map(x -> x + 1)
f = st.filter(x -> x % 2 === 0)

@time collect(f(1:2^20)); nothing
@time collect(m(1:2^20)); nothing
