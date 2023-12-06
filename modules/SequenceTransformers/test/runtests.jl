using SequenceTransformers
import SequenceTransformers as st

using Test


@testset "transforms" begin
  m = st.map(x -> x + 1)

  # Straight map
  @test Base.collect(m(1:5)) == 2:6

  f = st.filter(x -> x % 2 === 0)

  # Fewer out than in
  @test Base.collect(f(1:5)) == [2, 4]

  @test Base.collect(f(1:5)) == st.collect(f, 1:5)

  # More out than in
  @test Base.collect(st.flatten(([1,2,3], [4,5,6]))) == 1:6

  # composition
  @test Base.collect((f ∘ m)(1:5)) == [2,4,6]

end

p = x -> x % 2 == 0
f2 = x -> x + 1

m = st.map(f2)
f = st.filter(p)

@time Base.collect(f(1:2^20)); nothing
@time Base.collect(m(1:2^20)); nothing

GC.gc()
@time st.collect(f, 1:2^20); nothing
@time Base.filter(p, 1:2^20); nothing
@time Base.collect(Base.Iterators.filter(p, 1:2^20)); nothing

GC.gc()
@time st.collect(m, 1:2^20); nothing
@time Base.map(f2, 1:2^20); nothing
@time Base.collect(Base.Iterators.map(f2, 1:2^20)); nothing

GC.gc()
@time st.collect(m ∘ f, 1:2^20); nothing

# @code_warntype st.collect(m, 1:2^20)
# @code_warntype Base.collect(Base.Iterators.filter(p, 1:2^20))
