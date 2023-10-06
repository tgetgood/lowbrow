inc(x) = x + 1
even(x) = x % 2 == 0

@testset "Early Abort" begin
  @test take(5, 1:2^60) == vec(1:5)
  @test into(emptyvector, take(5) ∘ map(inc), 1:2^32) == vec(2:6)

  @test every(even, [1]) == false
  @test every(even, [1,2,3]) == false
  @test every(even, [2]) == true
  @test every(even, [2, 3]) == false
  @test every(even, 2:2:199) == true
  @test every(even, 1:2:199) == false

  xform() = every(even) ∘ map(x -> x^2) ∘ take(4)

  @test into(emptyvector, xform(), 2:100) == none
  @test into(emptyvector, xform(), 2:2:100) == vector(4, 16, 36, 64)

  @test into(emptyvector, take(5) ∘ take(5) ∘ take(5), vec(1:1000)) == vec(1:5)
end

@testset "Multiple Streams" begin
end
