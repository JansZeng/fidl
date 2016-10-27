// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package templates

const GenerateSourceFile = `
{{- define "GenerateSourceFile" -}}
//! This file was auto-generated by the Rust bindings generator.
#![allow(bad_style)]
#![allow(unused_imports)]
#![allow(unused_variables)]
#![allow(dead_code)]

use mojo::bindings::decoding;
use mojo::bindings::decoding::{Decoder, ValidationError};
use mojo::bindings::encoding;
use mojo::bindings::encoding::{Context, DataHeaderValue, DATA_HEADER_SIZE, Encoder};
use mojo::bindings::message;
use mojo::bindings::message::MessageHeader;
use mojo::bindings::mojom;
use mojo::bindings::mojom::{MojomEncodable, MojomPointer, MojomStruct,
                            MojomUnion, MojomMessage, MojomInterface,
			    MojomInterfaceSend, MojomInterfaceRecv,
			    MojomMessageOption, UNION_SIZE};

use mojo::system;
use mojo::system::{CastHandle, UntypedHandle};
use mojo::system::message_pipe;

use std::collections::HashMap;
use std::vec::Vec;

// Top-level constants:
{{range $const := .Constants -}}
pub const {{$const.Name}}: {{$const.Type}} = {{$const.Value}};
{{end}}

// Structs:
{{range $struct := .Structs -}}
{{template "GenerateStruct" $struct}}
{{end}}

// Mojom Unions:
{{range $union := .Unions -}}
{{template "GenerateUnion" $union}}
{{end}}

// Mojom Enums:
{{range $enum := .Enums -}}
{{template "GenerateEnum" $enum}}
{{end}}

// Interfaces:
{{range $interface := .Interfaces -}}
{{template "GenerateInterface" $interface}}
{{end}}

{{end}}
`
