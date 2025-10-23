/* Example 1: Traditional NS_IMPL_ISUPPORTS Pattern in XUL */

// From caps/DomainPolicy.h
class DomainPolicy final : public nsIDomainPolicy {
 public:
  NS_DECL_ISUPPORTS
  NS_DECL_NSIDOMAINPOLICY
  DomainPolicy();

 private:
  virtual ~DomainPolicy();
  
  RefPtr<DomainSet> mBlocklist;
  RefPtr<DomainSet> mSuperBlocklist;
  RefPtr<DomainSet> mAllowlist;
  RefPtr<DomainSet> mSuperAllowlist;
};

// From caps/DomainPolicy.cpp
NS_IMPL_ISUPPORTS(DomainPolicy, nsIDomainPolicy)

/*
 * NS_IMPL_ISUPPORTS expands to:
 * - AddRef() implementation with atomic refcounting
 * - Release() implementation with automatic deletion
 * - QueryInterface() with interface table lookup
 *
 * Pros:
 * - Reference counting built-in
 * - Binary compatible with XPCOM
 * - QueryInterface for runtime type checking
 * - Cycle collection support
 * - Thread safety checks
 * - Deep Firefox integration
 *
 * Cons:
 * - Complex macro expansion
 * - Requires understanding of COM concepts
 * - Verbose for simple cases
 * - Hard to debug macro issues
 * - Inheritance-based (can be limiting)
 */
