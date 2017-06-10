// Copyright 2017 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "application/lib/app/application_context.h"
#include "lib/fidl/cpp/bindings/binding_set.h"
#include "lib/fidl/cpp/bindings/interface_request.h"
#include "lib/ftl/macros.h"
#include "lib/mtl/tasks/message_loop.h"

#include "lib/fidl/examples/services/echo.fidl.h"

namespace echo {

class EchoImpl : public Echo {
 public:
  void AddBinding(fidl::InterfaceRequest<Echo> request) {
    bindings_.AddBinding(this, std::move(request));
  }

  void EchoString(const fidl::String& value,
                  const EchoStringCallback& callback) override {
    FTL_LOG(INFO) << "EchoString: " << value;
    callback(value);
  }

 private:
  fidl::BindingSet<Echo> bindings_;
};

class EchoDelegate {
 public:
  EchoDelegate()
    : context_(app::ApplicationContext::CreateFromStartupInfo()) {
    context_->outgoing_services()->AddService<Echo>(
      [this](fidl::InterfaceRequest<Echo> request) {
        echo_provider_.AddBinding(std::move(request));
      });
  }

  ~EchoDelegate() {}

 private:
  std::unique_ptr<app::ApplicationContext> context_;
  echo::EchoImpl echo_provider_;

  FTL_DISALLOW_COPY_AND_ASSIGN(EchoDelegate);
};

}  // namespace echo

int main(int argc, const char** argv) {
  mtl::MessageLoop loop;

  echo::EchoDelegate delegate;
  loop.Run();
  return 0;
}
