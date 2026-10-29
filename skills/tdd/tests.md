# Good and Bad Tests

_Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `engineering/tdd` and
[obra/superpowers](https://github.com/obra/superpowers) `test-driven-development` (both MIT)._

## Name the break first

Before writing the test body, name the production change that would make it fail, and check
that the change is a bug, not a decision. A test earns its place by catching a wrong branch, a
missing side effect, a wrong argument, an edge case, or a broken contract.

- **Can't name one?** Redesign the test around an observable behavior.
- **Only intentional decisions fail it?** That is a change detector: it fires on redesign and
  sleeps through bugs. A constant's value, exact message wording, or private structure are
  decisions. Test the behavior that depends on the decision: not `expect(MAX_RETRIES).toBe(5)`
  but "a failing call is retried 5 times and the 6th attempt never happens."
- **It checks source text?** Asserting that a script or config contains a line proves only
  that the source is the source. Run the script against controlled inputs and assert its
  output, side effects, or exit code.
- **It checks the framework?** Test the contract your code makes at its seams: the route you
  register, the query you emit, the payload you produce. Asserting that your router calls a
  registered handler is the framework's test. Constructors, getters, constants, and trivial
  forwarding earn a test only when they validate, normalize, default, derive, or cause side
  effects. Otherwise assert the first caller-visible result that depends on them.

## Good Tests

**Integration-style**: Test through real interfaces, not mocks of internal parts.

```typescript
// GOOD: Tests observable behavior
test("user can checkout with valid cart", async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe("confirmed");
});
```

Characteristics:

- Tests behavior users/callers care about
- Uses the public interface only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test. An "and" in the name means two tests.

## Bad Tests

**Implementation-detail tests**: Coupled to internal structure.

```typescript
// BAD: Tests implementation details
test("checkout calls paymentService.process", async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Red flags:

- Mocking internal collaborators
- Testing private methods
- Asserting on call counts/order of internal collaborators
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through external means instead of interface

```typescript
// BAD: Bypasses interface to verify
test("createUser saves to database", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// GOOD: Verifies through interface
test("createUser makes user retrievable", async () => {
  const user = await createUser({ name: "Alice" });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe("Alice");
});
```

**Tautological tests**: Expected value restates the implementation, so the test passes by construction.

```typescript
// BAD: Expected value is recomputed the way the code computes it
test("calculateTotal sums line items", () => {
  const items = [{ price: 10 }, { price: 5 }];
  const expected = items.reduce((sum, i) => sum + i.price, 0);
  expect(calculateTotal(items)).toBe(expected);
});

// GOOD: Expected value is an independent, known literal
test("calculateTotal sums line items", () => {
  expect(calculateTotal([{ price: 10 }, { price: 5 }])).toBe(15);
});
```

## The mutation check

Before finishing, mutate the production code in your head. At least one test fails for each
realistic mutation:

- Wrong constant or argument
- Wrong branch taken
- Missing state change or side effect
- Empty or default return
- Missing validation for zero, empty, nil, unauthorized, or malformed input

A mutation that no test catches marks the behavior as unprotected, or the test as
tautological. Where the language has a mutation tool (`cargo-mutants`, `mutmut`, Stryker), run
it instead.
