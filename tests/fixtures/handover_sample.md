## Summary
Fixed login validation bug and added unit tests for the auth middleware.

## What Was Done
- Fixed token validation in auth middleware to reject empty strings
- Added 3 unit tests for token validation edge cases

## What We Tried / Dead Ends
- Tried regex-based token validation but it was too strict for JWT format

## Bugs & Fixes
- Bug: Empty string tokens passed validation — fixed with explicit empty check

## Key Decisions (and Why)
- Chose explicit string check over regex for simplicity and readability

## Gotchas / Things to Watch Out For
- The auth middleware runs before CORS — order matters in the middleware stack

## Next Steps
- Add integration tests for the full login flow
- Review token expiry edge cases

## Important Files Map
- `src/middleware/auth.js` — Auth middleware with the fix
- `tests/auth.test.js` — New unit tests
