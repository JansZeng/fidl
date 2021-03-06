// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package rustgen

import (
	"log"
	"path/filepath"
	"strconv"
	"strings"

	"fidl/compiler/generated/fidl_files"
	"fidl/compiler/generated/fidl_types"
)

// TODO(vardhan): Make this file unittestable? This involves making it not crash
// on failure (so that we can test failure).
var reservedRustKeywords map[string]bool = map[string]bool{
	"as":       true,
	"box":      true,
	"break":    true,
	"const":    true,
	"continue": true,
	"crate":    true,
	"else":     true,
	"enum":     true,
	"extern":   true,
	"false":    true,
	"fn":       true,
	"for":      true,
	"if":       true,
	"impl":     true,
	"in":       true,
	"let":      true,
	"loop":     true,
	"match":    true,
	"mod":      true,
	"move":     true,
	"mut":      true,
	"pub":      true,
	"ref":      true,
	"return":   true,
	"self":     true,
	"Self":     true,
	"static":   true,
	"struct":   true,
	"super":    true,
	"trait":    true,
	"true":     true,
	"type":     true,
	"unsafe":   true,
	"use":      true,
	"where":    true,
	"while":    true,
	// Keywords reserved for future use (future-proofing...)
	"abstract": true,
	"alignof":  true,
	"become":   true,
	"do":       true,
	"final":    true,
	"macro":    true,
	"offsetof": true,
	"override": true,
	"priv":     true,
	"proc":     true,
	"pure":     true,
	"sizeof":   true,
	"typeof":   true,
	"unsized":  true,
	"virtual":  true,
	"yield":    true,

	// Weak keywords (special meaning in specific contexts)
	// These are ok in all contexts of fidl names.
	//"default":	true,
	//"union":	true,

	// Things that are not keywords, but for which collisions would be very unpleasant
	"Ok":     true,
	"Err":    true,
	"Vec":    true,
	"Option": true,
	"Some":   true,
	"None":   true,
	"Box":    true,
}

func isReservedKeyword(keyword string) bool {
	_, found := reservedRustKeywords[keyword]
	return found
}

func assertNotReservedKeyword(keyword string) string {
	if isReservedKeyword(keyword) {
		log.Fatalf("Generated name `%s` is a reserved Rust keyword.", keyword)
	}
	return keyword
}

// A map where keys are fidl names and values are Rust-mangled names.
type Names map[string]string

// Runs through the file graph and collects all names putting them into a Names map which
// is a map from the original name to the mangled name
func CollectAllNames(fileGraph *fidl_files.FidlFileGraph, file *fidl_files.FidlFile) *Names {
	names := make(Names)
	// Collect all top-level constant names
	if file.DeclaredFidlObjects.TopLevelConstants != nil {
		for _, fidlConstKey := range *(file.DeclaredFidlObjects.TopLevelConstants) {
			fidlConst := fileGraph.ResolvedConstants[fidlConstKey]
			names[*fidlConst.DeclData.ShortName] = *fidlConst.DeclData.ShortName
		}
	}

	// Collect all top-level enum names
	if file.DeclaredFidlObjects.TopLevelEnums != nil {
		for _, fidlEnumKey := range *(file.DeclaredFidlObjects.TopLevelEnums) {
			fidlEnum := fileGraph.ResolvedTypes[fidlEnumKey].Interface().(fidl_types.FidlEnum)
			names[*fidlEnum.DeclData.ShortName] = *fidlEnum.DeclData.ShortName
		}
	}

	// Collect all union names
	if file.DeclaredFidlObjects.Unions != nil {
		for _, fidlUnionKey := range *(file.DeclaredFidlObjects.Unions) {
			fidlUnion := fileGraph.ResolvedTypes[fidlUnionKey].Interface().(fidl_types.FidlUnion)
			names[*fidlUnion.DeclData.ShortName] = *fidlUnion.DeclData.ShortName
		}
	}

	// Collect all struct names
	if file.DeclaredFidlObjects.Structs != nil {
		for _, fidlStructKey := range *(file.DeclaredFidlObjects.Structs) {
			fidlStruct := fileGraph.ResolvedTypes[fidlStructKey].Interface().(fidl_types.FidlStruct)
			names[*fidlStruct.DeclData.ShortName] = *fidlStruct.DeclData.ShortName
		}
	}

	// Collect all interface names
	if file.DeclaredFidlObjects.Interfaces != nil {
		for _, fidlIfaceKey := range *(file.DeclaredFidlObjects.Interfaces) {
			fidlIface := fileGraph.ResolvedTypes[fidlIfaceKey].Interface().(fidl_types.FidlInterface)
			names[*fidlIface.DeclData.ShortName] = *fidlIface.DeclData.ShortName
			// Pre-mangle all the method names since we know exactly how they look
			for _, fidlMethod := range fidlIface.Methods {
				method_name := *fidlMethod.DeclData.ShortName
				names[method_name+"-request"] = method_name + "_Request"
				names[method_name+"-response"] = method_name + "_Response"
			}
		}
	}
	// Contained declarations do not need to be handled because they are prepended with
	// their mangled parent's names.
	return &names
}

// Removes the namespace from a full identifier are returns the mangled name
// for the identifier or type.
func removeNamespaceFromIdentifier(context *Context, file *fidl_files.FidlFile, ident string) string {
	var namespace string
	if file.ModuleNamespace != nil {
		namespace = *file.ModuleNamespace + "."
	} else {
		namespace = ""
	}
	name := strings.Replace(ident, namespace, "", 1)
	portions := strings.Split(name, ".")
	portions[0] = context.GetNameFromFile(portions[0], file)
	return strings.Join(portions, "")
}

// Given a name (described in fidl IDL), return a Rust-mangled name.
func fidlToRustName(decl *fidl_types.DeclarationData, context *Context, fmt func(string) string) string {
	// Might not have a full identifier; use a ShortName instead
	if decl.FullIdentifier == nil {
		return mangleReservedKeyword(fmt(context.GetName(*decl.ShortName)))
	}
	// No need to specify path if the name is defined in the current file
	src_file_name := decl.SourceFileInfo.FileName
	if src_file_name == context.File.FileName {
		name := removeNamespaceFromIdentifier(context, context.File, *decl.FullIdentifier)
		return mangleReservedKeyword(fmt(name))
	}
	relpath, err := filepath.Rel(context.SrcRootPath, src_file_name)
	if err != nil {
		log.Fatal(err.Error())
	}
	src_file := context.FileGraph.Files[src_file_name]
	name := removeNamespaceFromIdentifier(context, &src_file, *decl.FullIdentifier)
	crates, present := (*context.Map)["//"+relpath]
	if !present {
		relThisPath, _ := filepath.Rel(context.SrcRootPath, context.File.FileName)
		log.Fatal("Unresolved dependency: ", relThisPath, " depends on ", relpath,
			" but not in dependency map.")
	}
	if len(crates) == 0 {
		return "::" + mangleReservedKeyword(fmt(name))
	}
	return "::" + crates + "::" + mangleReservedKeyword(fmt(name))
}

func fidlToRustBuiltinValue(val fidl_types.BuiltinConstantValue) string {
	switch val {
	case fidl_types.BuiltinConstantValue_DoubleNegativeInfinity:
		return "::std::f64::NEG_INFINITY"
	case fidl_types.BuiltinConstantValue_FloatNegativeInfinity:
		return "::std::f32::NEG_INFINITY"
	case fidl_types.BuiltinConstantValue_DoubleInfinity:
		return "::std::f64::INFINITY"
	case fidl_types.BuiltinConstantValue_FloatInfinity:
		return "::std::f32::INFINITY"
	case fidl_types.BuiltinConstantValue_DoubleNan:
		return "::std::f64::NAN"
	case fidl_types.BuiltinConstantValue_FloatNan:
		return "::std::f32::NAN"
	}
	log.Fatal("Unknown builtin constant", val)
	return ""
}

// A fidl type name-mangled to Rust type.
func fidlToRustType(t fidl_types.Type, context *Context) string {
	switch t.(type) {
	case *fidl_types.TypeSimpleType:
		return simpleTypeToRustType(t.Interface().(fidl_types.SimpleType))
	case *fidl_types.TypeArrayType:
		array_type := t.Interface().(fidl_types.ArrayType)
		elem_type_str := fidlToRustType(array_type.ElementType, context)
		var type_str string
		if array_type.FixedLength < 0 {
			type_str = "Vec<" + elem_type_str + ">"
		} else if array_type.FixedLength <= 32 {
			// Regrettably, because Rust doesn't allow you to be generic over
			// fixed array sizes, we only support checking lengths of up to
			// and including 32.
			len_str := strconv.Itoa(int(array_type.FixedLength))
			type_str = "[" + elem_type_str + "; " + len_str + "]"
		} else {
			log.Fatal("Rust doesn't currently support arrays of " +
				"fixed size greater than 32. The reason for this is " +
				"the lack of generics over array length in the type " +
				"system. Since we cannot encode the length in the type " +
				"there is no way for nested decode routines to know " +
				"what length it should be. Sorry. :(")
			// Fixed length array, but user has to validate the length themselves.
			//type_str = "Box<[" + elem_type_str + "]>"
		}
		if array_type.Nullable {
			return "Option<" + type_str + ">"
		}
		return type_str
	case *fidl_types.TypeMapType:
		map_type := t.Interface().(fidl_types.MapType)
		key_type_str := fidlToRustType(map_type.KeyType, context)
		value_type_str := fidlToRustType(map_type.ValueType, context)
		type_str := "::std::collections::HashMap<" + key_type_str + ", " + value_type_str + ">"
		if map_type.Nullable {
			return "Option<" + type_str + ">"
		}
		return type_str
	case *fidl_types.TypeStringType:
		string_type := t.Interface().(fidl_types.StringType)
		if string_type.Nullable {
			return "Option<String>"
		}
		return "String"
	case *fidl_types.TypeHandleType:
		handle_type := t.Interface().(fidl_types.HandleType)
		var type_str string
		// Note that not all of these handle types are currently supported in magenta-rs.
		switch handle_type.Kind {
		case fidl_types.HandleType_Kind_Channel:
			type_str = "::magenta::Channel"
		case fidl_types.HandleType_Kind_Vmo:
			type_str = "::magenta::Vmo"
		case fidl_types.HandleType_Kind_Process:
			type_str = "::magenta::Process"
		case fidl_types.HandleType_Kind_Thread:
			type_str = "::magenta::Thread"
		case fidl_types.HandleType_Kind_Event:
			type_str = "::magenta::Event"
		case fidl_types.HandleType_Kind_Port:
			type_str = "::magenta::Port"
		case fidl_types.HandleType_Kind_Job:
			type_str = "::magenta::Job"
		case fidl_types.HandleType_Kind_Socket:
			type_str = "::magenta::Socket"
		case fidl_types.HandleType_Kind_EventPair:
			type_str = "::magenta::EventPair"
		case fidl_types.HandleType_Kind_Unspecified:
			type_str = "::magenta::Handle"
		default:
			log.Fatal("Unknown handle type kind! ", handle_type.Kind)
		}
		if handle_type.Nullable {
			return "Option<" + type_str + ">"
		}
		return type_str
	case *fidl_types.TypeTypeReference:
		typ_ref := t.Interface().(fidl_types.TypeReference)
		resolved_type := context.FileGraph.ResolvedTypes[*typ_ref.TypeKey]
		type_str := userDefinedTypeToRustType(&resolved_type, context, typ_ref.IsInterfaceRequest)
		if typ_ref.Nullable {
			if fidlUserTypeNeedsBoxing(resolved_type) {
				return "Option<Box<" + type_str + ">>"
			} else {
				return "Option<" + type_str + ">"
			}
		}
		return type_str
	default:
		log.Fatal("Should not be here! ", t.Interface())
	}

	return ""
}

// Formats a literal value suitable for use as a const
func fidlToRustLiteral(value fidl_types.LiteralValue) string {
	val := value.Interface()
	switch value.(type) {
	case *fidl_types.LiteralValueBoolValue:
		return strconv.FormatBool(val.(bool))
	case *fidl_types.LiteralValueDoubleValue:
		return strconv.FormatFloat(val.(float64), 'g', -1, 64)
	case *fidl_types.LiteralValueFloatValue:
		return strconv.FormatFloat(float64(val.(float32)), 'g', -1, 32)
	case *fidl_types.LiteralValueInt8Value:
		return strconv.FormatInt(int64(val.(int8)), 10)
	case *fidl_types.LiteralValueInt16Value:
		return strconv.FormatInt(int64(val.(int16)), 10)
	case *fidl_types.LiteralValueInt32Value:
		return strconv.FormatInt(int64(val.(int32)), 10)
	case *fidl_types.LiteralValueInt64Value:
		return strconv.FormatInt(int64(val.(int64)), 10)
	case *fidl_types.LiteralValueUint8Value:
		return strconv.FormatUint(uint64(val.(uint8)), 10)
	case *fidl_types.LiteralValueUint16Value:
		return strconv.FormatUint(uint64(val.(uint16)), 10)
	case *fidl_types.LiteralValueUint32Value:
		return strconv.FormatUint(uint64(val.(uint32)), 10)
	case *fidl_types.LiteralValueUint64Value:
		return strconv.FormatUint(uint64(val.(uint64)), 10)
	case *fidl_types.LiteralValueStringValue:
		// TODO(raph): Do we have to do any string escaping here?
		return "\"" + val.(string) + "\""
	default:
		log.Fatal("Should not reach here. Unknown literal type:", value)
	}

	return ""
}

// Make sure the literal follows the rules for float
func floatifyRustLiteral(repr string) string {
	for i := 0; i < len(repr); i++ {
		if !(repr[i] == '-' || (repr[i] >= '0' && repr[i] <= '9')) {
			return repr
		}
	}
	return repr + ".0"
}

func fidlUnionToRustType(u *fidl_types.FidlUnion, context *Context) string {
	return fidlToRustName(u.DeclData, context, ident)
}

func userDefinedTypeToRustType(t *fidl_types.UserDefinedType, context *Context, interfaceRequest bool) string {
	switch (*t).(type) {
	case *fidl_types.UserDefinedTypeStructType:
		full_name := fidlToRustName((*t).Interface().(fidl_types.FidlStruct).DeclData, context, ident)
		return full_name
	case *fidl_types.UserDefinedTypeEnumType:
		full_name := fidlToRustName((*t).Interface().(fidl_types.FidlEnum).DeclData, context, ident)
		return full_name
	case *fidl_types.UserDefinedTypeUnionType:
		full_name := fidlToRustName((*t).Interface().(fidl_types.FidlUnion).DeclData, context, ident)
		return full_name
	case *fidl_types.UserDefinedTypeInterfaceType:
		full_name := fidlToRustName((*t).Interface().(fidl_types.FidlInterface).DeclData, context, ident)
		if interfaceRequest {
			return "::fidl::ServerEnd<" + full_name + "::Marker>"
		}
		return "::fidl::InterfacePtr<::fidl::ClientEnd<" + full_name + "::Marker>>"
	}
	log.Fatal("Unknown UserDefinedType", t)
	return ""
}

func simpleTypeToRustType(st fidl_types.SimpleType) string {
	switch st {
	case fidl_types.SimpleType_Int8:
		return "i8"
	case fidl_types.SimpleType_Int16:
		return "i16"
	case fidl_types.SimpleType_Int32:
		return "i32"
	case fidl_types.SimpleType_Int64:
		return "i64"
	case fidl_types.SimpleType_Uint8:
		return "u8"
	case fidl_types.SimpleType_Uint16:
		return "u16"
	case fidl_types.SimpleType_Uint32:
		return "u32"
	case fidl_types.SimpleType_Uint64:
		return "u64"
	case fidl_types.SimpleType_Float:
		return "f32"
	case fidl_types.SimpleType_Double:
		return "f64"
	case fidl_types.SimpleType_Bool:
		return "bool"
	default:
		log.Fatal("Unknown Simple type:", st)
	}
	return ""
}

func fidlTypeIsBool(typ fidl_types.Type) bool {
	switch typ.(type) {
	case *fidl_types.TypeSimpleType:
		if typ.Interface().(fidl_types.SimpleType) == fidl_types.SimpleType_Bool {
			return true
		}
	}
	return false
}

func fidlTypeIsUnion(typ fidl_types.Type, context *Context) bool {
	switch typ.(type) {
	case *fidl_types.TypeTypeReference:
		type_key := *typ.Interface().(fidl_types.TypeReference).TypeKey
		switch context.FileGraph.ResolvedTypes[type_key].(type) {
		case *fidl_types.UserDefinedTypeUnionType:
			return true
		}
	}
	return false
}

func fidlAlignToBytes(size uint32, alignment uint32) uint32 {
	diff := size % alignment
	if alignment == 0 || diff == 0 {
		return size
	}
	return size + alignment - diff
}

func fidlTypeSize(typ fidl_types.Type, context *Context) uint32 {
	switch typ.(type) {
	case *fidl_types.TypeSimpleType:
		switch typ.Interface().(fidl_types.SimpleType) {
		case fidl_types.SimpleType_Bool:
			log.Fatal("Simple type bool does not have a size in bytes!")
		case fidl_types.SimpleType_Double:
			return 8
		case fidl_types.SimpleType_Float:
			return 4
		case fidl_types.SimpleType_Int8:
			return 1
		case fidl_types.SimpleType_Int16:
			return 2
		case fidl_types.SimpleType_Int32:
			return 4
		case fidl_types.SimpleType_Int64:
			return 8
		case fidl_types.SimpleType_Uint8:
			return 1
		case fidl_types.SimpleType_Uint16:
			return 2
		case fidl_types.SimpleType_Uint32:
			return 4
		case fidl_types.SimpleType_Uint64:
			return 8
		default:
			log.Fatal("Invalid simple type:", typ.Interface().(fidl_types.SimpleType))
		}
	case *fidl_types.TypeStringType:
		return 8
	case *fidl_types.TypeArrayType:
		return 8
	case *fidl_types.TypeMapType:
		return 8
	case *fidl_types.TypeHandleType:
		return 4
	case *fidl_types.TypeTypeReference:
		return referenceTypeSize(typ.Interface().(fidl_types.TypeReference), context)
	default:
		log.Fatal("Should not be here. Unknown fidl type size for:", typ)
	}
	return 0
}

func referenceTypeSize(typ fidl_types.TypeReference, context *Context) uint32 {
	if typ.IsInterfaceRequest {
		return 4
	}

	udt := context.FileGraph.ResolvedTypes[*typ.TypeKey]
	switch udt.(type) {
	case *fidl_types.UserDefinedTypeEnumType:
		return 4
	case *fidl_types.UserDefinedTypeStructType:
		return 8
	case *fidl_types.UserDefinedTypeUnionType:
		return 16
	case *fidl_types.UserDefinedTypeInterfaceType:
		return 8 // TODO(raph): this is wrong if it's an interface request
	}
	log.Fatal("Uhoh, should not be here.", udt.Interface())
	return 0
}

func fidlTypeNeedsBoxing(typ fidl_types.Type, context *Context) bool {
	switch typ.(type) {
	case *fidl_types.TypeTypeReference:
		typ_ref := typ.Interface().(fidl_types.TypeReference)
		resolved_type := context.FileGraph.ResolvedTypes[*typ_ref.TypeKey]
		return fidlUserTypeNeedsBoxing(resolved_type)
	}
	return false
}

// Return true if the type is an aggregate type that needs boxing if it's optional.
// Note: this could become considerably more lenient. For example, a struct that
// contains no references to other structs or unions is ok to not box. In theory,
// the only time boxing is required is when the type is recursive.
func fidlUserTypeNeedsBoxing(typ fidl_types.UserDefinedType) bool {
	switch typ.(type) {
	case *fidl_types.UserDefinedTypeStructType:
		return true
	case *fidl_types.UserDefinedTypeUnionType:
		return true
	}
	return false
}
