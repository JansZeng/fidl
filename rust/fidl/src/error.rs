// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Error (common to all fidl operations)

use std::io;
use std::result;

pub type Result<T> = result::Result<T, Error>;

#[derive(Debug)]
pub enum Error {
    InvalidHeader,
    Invalid,
    OutOfRange,
    NotNullable,
    Utf8Error,
    InvalidHandle,
    UnknownOrdinal,
    UnknownUnionTag,
    RemoteClosed,
    IoError(io::Error),
}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Error {
        Error::IoError(error)
    }
}
