// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package templates

const GenerateEndpoint = `
{{- /* . (dot) refers to a string which is the endpoint's name */ -}}
{{- define "GenerateEndpoint" -}}
{{- $endpoint := .Name -}}
{{- $interface := .Interface -}}

pub struct {{$endpoint}}(::magenta::Channel);

impl ::magenta::HandleRef for {{$endpoint}} {
    fn as_handle_ref(&self) -> ::magenta::HandleRef {
        self.0.get_ref()
    }
}

impl Into<::magenta::Handle> for {{$endpoint}} {
    fn into(self) -> ::magenta::Handle {
        {{$endpoint}}(::magenta::Channel::from(handle))
    }
}

impl From<::magenta::Handle> for {{$endpoint}} {
    fn from(hande: ::magenta::Handle) -> Self {
        self.0.into()
    }
}

impl ::magenta::HandleBased for {{$endpoint}}

impl_codable_handle!({{$endpoint}});

{{- end -}}
`

const GenerateInterface = `
{{- /* . (dot) refers to the Go type |rustgen.InterfaceTemplate| */ -}}
{{- define "GenerateInterface" -}}
{{- $interface := . -}}
// --- {{$interface.Name}} ---

pub use {{$interface.Name}}::I as {{$interface.Name}}_I;

pub mod {{$interface.Name}} {
    use fidl::{self, DecodeBuf, EncodeBuf, EncodablePtr, DecodablePtr, Stub};
    use futures::{BoxFuture, Future, future};
    use magenta;
    use tokio_core::reactor;
    use super::*;
    pub const SERVICE_NAME: &'static str = "{{$interface.ServiceName}}";
    pub const VERSION: u32 = {{$interface.Version}};

    pub struct Marker;

    pub trait I {
{{range $message := $interface.Messages}}        fn {{$message.Name}}(&mut self
{{- range $index, $field := $message.RequestStruct.Fields -}}
    , {{$field.Name}}: {{$field.Type}}
{{- end -}}
)
    {{- if ne $message.ResponseStruct.Name "" }} -> BoxFuture<{{template "GenerateResponseType" $message.ResponseStruct}}, fidl::Error>{{end}};
{{end}}    }

    pub struct Dispatcher<T: self::I>(pub T);

    impl<T: self::I> Stub for Dispatcher<T> {
        fn dispatch_with_response(&mut self, request: &mut DecodeBuf) -> BoxFuture<EncodeBuf, fidl::Error> {
            let name: u32 = ::fidl::Decodable::decode(request, 0, 8).unwrap();
            match name {
{{range $message := $interface.Messages}}{{if ne $message.ResponseStruct.Name ""}}                {{$message.MessageOrdinal}} => self.
    {{- $message.RawName}}(request),
{{end}}{{end}}                _ => Box::new(future::err(fidl::Error::UnknownOrdinal))
            }
        }

        fn dispatch(&mut self, request: &mut ::fidl::DecodeBuf) -> Result<(), fidl::Error> {
            let name: u32 = ::fidl::Decodable::decode(request, 0, 8).unwrap();
            match name {
{{range $message := $interface.Messages}}{{if eq $message.ResponseStruct.Name ""}}                {{$message.MessageOrdinal}} => self.
    {{- $message.RawName}}(request),
{{end}}{{end}}                _ => Err(::fidl::Error::UnknownOrdinal)
            }
        }
    }

    impl<T: self::I> Dispatcher<T> {
{{- range $message := $interface.Messages}}
        fn {{$message.RawName}}(&mut self, request: &mut fidl::DecodeBuf)
            {{- if eq $message.ResponseStruct.Name "" }} -> Result<(), fidl::Error> {
            let request: {{$message.RequestStruct.Name}} = try!(::fidl::DecodablePtr::decode_obj(request, 16));
            self.0.{{$message.Name}}(
{{- range $index, $field := $message.RequestStruct.Fields -}}
    {{- if $index}}, {{end -}}
    request.{{- $field.Name -}}
{{- end -}}
                );
            Ok(())
        }
        {{- else}} -> BoxFuture<EncodeBuf, fidl::Error> {
            let r: ::fidl::Result<{{$message.RequestStruct.Name}}> = ::fidl::DecodablePtr::decode_obj(request, 24);
            match r {
                Ok(request) => Box::new(self.0.{{$message.Name}}(
{{- range $index, $field := $message.RequestStruct.Fields -}}
    {{- if $index}}, {{end -}}
    request.{{- $field.Name -}}
{{- end -}}
            ).map(|
{{- if ne 1 (len $message.ResponseStruct.Fields) -}} ( {{- end -}}
{{- range $index, $field := $message.ResponseStruct.Fields -}}
    {{- if $index}}, {{end -}}
    {{- $field.Name -}}
{{- end -}}
{{- if ne 1 (len $message.ResponseStruct.Fields) -}} ) {{- end -}}
                    | {
                    let response = {{$message.ResponseStruct.Name}} {
{{range $field := $message.ResponseStruct.Fields}}                        {{$field.Name}}: {{$field.Name}},
{{end}}                    };
                    let mut encode_buf = ::fidl::EncodeBuf::new_response({{$message.MessageOrdinal}});
                    ::fidl::EncodablePtr::encode_obj(response, &mut encode_buf);
                    encode_buf
                })),
                Err(error) => Box::new(future::err(error))
            }
        }{{end}}
{{end}}    }


    pub struct Proxy(fidl::Client);

    // This is implemented as a module-level function because Proxy::new could collide with fidl methods.
    pub fn new_proxy(client_end: fidl::ClientEnd<Marker>, handle: &reactor::Handle) -> Result<Proxy, ::fidl::Error> {
        let channel = ::tokio_fuchsia::Channel::from_channel(::magenta::Channel::from(
            <fidl::ClientEnd<Marker> as Into<::magenta::Handle>>::into(client_end)
        ), handle)?;
        Ok(Proxy(fidl::Client::new(channel, handle)))
    }

    pub fn new_pair(handle: &reactor::Handle) -> Result<(Proxy, fidl::ServerEnd<Marker>), ::fidl::Error> {
        let (s1, s2) = magenta::Channel::create(magenta::ChannelOpts::Normal).unwrap();
        let client_end = fidl::ClientEnd::new(s1);
        let server_end = fidl::ServerEnd::new(s2);
        Ok((new_proxy(client_end, handle)?, server_end))
    }

    impl I for Proxy {
    {{- range $message := $interface.Messages}}
        fn {{$message.Name}}(&mut self
    {{- range $field := $message.RequestStruct.Fields}}, {{$field.Name}}: {{$field.Type}}
    {{- end -}} )
    {{- if ne $message.ResponseStruct.Name "" }} -> BoxFuture<{{template "GenerateResponseType" $message.ResponseStruct}}, fidl::Error>
    {{- end}} {
            let request = {{$message.RequestStruct.Name}} {
{{range $field := $message.RequestStruct.Fields}}                {{$field.Name}}: {{$field.Name}},
{{end}}            };
            let mut encode_buf = ::fidl::EncodeBuf::new_request{{if ne $message.ResponseStruct.Name "" -}}
                _expecting_response
            {{- end}}({{$message.MessageOrdinal}});
            ::fidl::EncodablePtr::encode_obj(request, &mut encode_buf);
{{if eq $message.ResponseStruct.Name ""}}            self.0.send_msg(&mut encode_buf);
{{else}}            Box::new(self.0.send_msg_expect_response(encode_buf).and_then(|mut decode_buf| {
                let r: {{$message.ResponseStruct.Name}} = try!(::fidl::DecodablePtr::decode_obj(&mut decode_buf, 24));
                Ok(
{{- if ne 1 (len $message.ResponseStruct.Fields) -}} ( {{- end -}}
{{- range $index, $field := $message.ResponseStruct.Fields -}}
{{- if $index}}, {{end -}}
r.{{- $field.Name -}}
{{- end -}}
{{- if ne 1 (len $message.ResponseStruct.Fields) -}} ) {{- end -}}
                )
            }))
{{end}}        }
{{end}}    }

}

// Enums
{{range $enum := $interface.Enums -}}
{{template "GenerateEnum" $enum}}
{{end}}

// Constants
{{range $const := $interface.Constants -}}
pub const {{$const.Name}}: {{$const.Type}} = {{$const.Value}};
{{end}}

{{range $message := $interface.Messages -}}
/// Message: {{$message.Name}}
{{template "GenerateStruct" $message.RequestStruct}}

{{if ne $message.ResponseStruct.Name "" -}}
{{template "GenerateStruct" $message.ResponseStruct}}

{{end -}}
{{- end -}}
{{- end -}}

{{- /* . (dot) refers to the Go type |rustgen.StructTemplate| */ -}}
{{- define "GenerateResponseType" -}}
{{- $struct := . -}}
{{- if ne 1 (len $struct.Fields) -}} ( {{- end -}}
{{- range $index, $field := $struct.Fields -}}
{{- if $index}}, {{end -}}
{{- $field.Type -}}
{{- end -}}
{{- if ne 1 (len $struct.Fields) -}} ) {{- end -}}
{{- end -}}
`
