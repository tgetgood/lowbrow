@testset "vectors" begin
  # There's only one empty vector
  @test emptyvector === vector()

  @test emptyp(emptyvector)

  @test !emptyp(vector(1))
  @test !emptyp(into(emptyvector, 1:nodelength^2))

  @test vector(1) == conj(emptyvector, 1)

  # proper upgrading of element type
  @test conj(conj(emptyvector, 1), :sym) == vector(1, :sym)

  @test begin
    a = vector(:a, :b, :c)

    b = conj(a, :d)

    count(a) == 3 && count(b) == 4
  end

  a::Vector = 1:nodelength

  @test count(a) == nodelength

  @test nth(a, 1) === first(a)
  @test nth(a, 2) === first(rest(a))

  @test nth(a, 15) == 15

  b = conj(a, :another)

  @test typeof(a) != typeof(b)

  @test first(b.elements) === a

  @test vec(1:nodelength+1) == into(emptyvector, 1:nodelength+1)
  @test vec(1:nodelength^2+1) == into(emptyvector, 1:nodelength^2+1)

end

@testset "balanced trees" begin
  # TODO: My vectors are not balanced trees. So long as you're just iterating, I
  # don't think this is a big deal, but the asymptotic lookup behaviour is O(n)
  # instead of O(log(n)) which is a big deal.

  @test begin
    x::Vector = 1:nodelength
    depth(x) == 1
  end

  @test depth(vec(1:nodelength^2)) == 2

  @test depth(vec(1:nodelength^3)) == 3

  long::Vector = 1:nodelength^3 + 2

  @test count(long) == nodelength^3 + 2
  @test depth(long) == 4
  @test every(x -> isa(x, VectorNode), long.elements)
  @test every(x -> isa(x, VectorNode), last(long.elements).elements)
  @test every(x -> isa(x, VectorLeaf), last(first(long.elements).elements).elements)

  @test count(long) == sum(map(count, long.elements))

end

@testset "vector seqs" begin
  #TODO:
end
