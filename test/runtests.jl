import Test as t
using brow

# t.@test 2 == 5

t.@test_throws AssertionError parseurl("asd")
