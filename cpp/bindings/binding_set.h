// Copyright 2014 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef LIB_FIDL_CPP_BINDINGS_BINDING_SET_H_
#define LIB_FIDL_CPP_BINDINGS_BINDING_SET_H_

#include <assert.h>

#include <algorithm>
#include <memory>
#include <utility>
#include <vector>

#include "lib/ftl/macros.h"
#include "lib/fidl/cpp/bindings/binding.h"

namespace fidl {

// Use this class to manage a set of bindings each of which is
// owned by the channel it is bound to.
//
// The implementation type of the binding is also parameterized, allowing
// the use of smart pointer types such as |std::unique_ptr<>| to reference
// the implementation.
template <typename Interface, typename ImplPtr = Interface*>
class BindingSet {
 public:
  using Binding = ::fidl::Binding<Interface, ImplPtr>;

  BindingSet() {}
  ~BindingSet() { CloseAllBindings(); }

  // Adds a binding to the list and arranges for it to be removed when
  // a connection error occurs.  Does not take ownership of |impl|, which
  // must outlive the binding set.
  void AddBinding(ImplPtr impl, InterfaceRequest<Interface> request) {
    bindings_.emplace_back(
        new Binding(std::forward<ImplPtr>(impl), std::move(request)));
    auto* binding = bindings_.back().get();
    // Set the connection error handler for the newly added Binding to be a
    // function that will erase it from the vector.
    binding->set_connection_error_handler(
        std::bind(&BindingSet::RemoveOnError, this, binding));
  }

  // Adds a binding to the list and arranges for it to be removed when
  // a connection error occurs.  Does not take ownership of |impl|, which
  // must outlive the binding set.
  InterfaceHandle<Interface> AddBinding(ImplPtr impl) {
    bindings_.emplace_back(new Binding(std::forward<ImplPtr>(impl)));
    auto* binding = bindings_.back().get();
    InterfaceHandle<Interface> interface;
    binding->Bind(&interface);
    // Set the connection error handler for the newly added Binding to be a
    // function that will erase it from the vector.
    binding->set_connection_error_handler(
        std::bind(&BindingSet::RemoveOnError, this, binding));

    return std::move(interface);
  }

  void CloseAllBindings() { bindings_.clear(); }

  size_t size() const { return bindings_.size(); }

  void set_on_empty_set_handler(const ftl::Closure& on_empty_set_handler) {
    on_empty_set_handler_ = on_empty_set_handler;
  }

 private:
  void RemoveOnError(Binding* binding) {
    auto it = std::find_if(bindings_.begin(), bindings_.end(),
                           [binding](const std::unique_ptr<Binding>& b) {
                             return (b.get() == binding);
                           });
    assert(it != bindings_.end());
    bindings_.erase(it);
    if (bindings_.empty() && on_empty_set_handler_)
      on_empty_set_handler_();
  }

  std::vector<std::unique_ptr<Binding>> bindings_;
  ftl::Closure on_empty_set_handler_;

  FTL_DISALLOW_COPY_AND_ASSIGN(BindingSet);
};

}  // namespace fidl

#endif  // LIB_FIDL_CPP_BINDINGS_BINDING_SET_H_
