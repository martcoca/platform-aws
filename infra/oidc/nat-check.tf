# TEMPORARY — proves the cost guard blocks a real plan, not just a fixture.
# A NAT gateway is ~$32/mo and sits on the ADR-0006 denylist. Planning one costs
# nothing; this is never applied. Removed once CI has failed on it.
resource "aws_nat_gateway" "guard_check" {
  allocation_id = "eipalloc-00000000000000000"
  subnet_id     = "subnet-00000000000000000"
}
