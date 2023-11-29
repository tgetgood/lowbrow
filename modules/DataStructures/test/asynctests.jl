@testset "transduction on channels" begin
  ch = Channel(5)
  for i in 1:5
    put!(ch, i)
  end

  @async close(ch)

  @test reduce(+, 0, ch) == 15

  c2 = Channel(6)
  put!(c2, 0)
  close(c2)

  c3 = Channel(5)
  for i in 1:5
    put!(c3, i)
  end

  @test reduce(+, 0, c2, c3) == 1
end
