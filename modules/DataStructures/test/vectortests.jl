@testset "vectors" begin
  # There's only one empty vector
  @test emptyvector === vector()

  @test vector(1) == conj(emptyvector, 1)

  # proper upgrading of element type
  @test conj(conj(emptyvector, 1), :sym) == vector(1, :sym)

  @test begin
    a = vector(:a, :b, :c)

    b = conj(a, :d)

    count(a) == 3 && count(b) == 4
  end

  a = into(emptyvector, 1:nodelength)
  @test count(a) == nodelength

  b = conj(a, :another)

  @test typeof(a) != typeof(b)
  # FIXME: This will break if we implement another kind of vector
  @test first(b.elements) === a
end
