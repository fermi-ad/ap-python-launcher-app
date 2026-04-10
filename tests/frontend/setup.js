// Global mocks applied before every test suite.

// fetch is not available in jsdom; provide a jest mock.
global.fetch = jest.fn();

// Ensure localStorage is reset between tests.
beforeEach(() => {
  localStorage.clear();
  jest.clearAllMocks();
});
