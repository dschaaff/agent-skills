# When to Mock

_Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `engineering/tdd` and
[obra/superpowers](https://github.com/obra/superpowers) `test-driven-development` (both MIT)._

Mock only at seams where an external dependency sits:

- External services (payment, email, etc.)
- Databases (sometimes - prefer test DB)
- Time/randomness
- File system (sometimes)

Don't mock:

- Your own classes/modules
- Internal collaborators
- Anything you control

## Designing for Mockability

At those seams, design interfaces that are easy to mock:

**1. Use dependency injection**

Pass external dependencies in rather than creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

**2. Prefer SDK-style interfaces over generic fetchers**

Create specific functions for each external operation instead of one generic function with conditional logic:

```typescript
// GOOD: Each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: Mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach means:

- Each mock returns one specific shape
- No conditional logic in test setup
- Easier to see which endpoints a test exercises
- Type safety per endpoint

## Using a mock

**Assert on the real component, never on the mock.** An assertion that passes when the mock is
present and fails when it is absent says nothing about your code. Ask: "Am I testing the
behavior of a mock?"

```typescript
// GOOD: Real behavior
expect(screen.getByRole("navigation")).toBeInTheDocument();

// BAD: Mock existence
expect(screen.getByTestId("sidebar-mock")).toBeInTheDocument();
```

**Mock at the right level.** List every side effect of the real method before you replace
it. Mock the slow or external operation below it, and keep real what the test depends on. When
unsure, run the test against the real implementation first and see what actually happens.

```typescript
// BAD: The mock swallows the config write that duplicate detection reads
vi.mock("ToolCatalog", () => ({
  discoverAndCacheTools: vi.fn().mockResolvedValue(undefined),
}));

// GOOD: Mock only the slow server startup; the config write stays real
vi.mock("MCPServerManager");
```

**Make doubles specific.** When arguments, call counts, or ordering at the external seam are
part of the contract, assert them: a fake that accepts anything verifies nothing. Give each
branch (success, error, malformed) its own fixture, so the wrong branch cannot satisfy the
expectation.

**Mirror real data completely.** A mock response has the full structure the real one has, not
only the fields this test reads. A partial mock passes while integration breaks on the first
field downstream code reads that the mock left out.

**Keep test-only code out of production.** Cleanup or setup that only tests need lives in test
utilities, not as a `destroy()` on the production class.

**Switch to real components when mocks balloon.** Mock setup longer than the test logic, mocks
missing methods the real thing has, or tests that break when the mock changes all mean an
integration test with real components is the better test.
