# Packed Column Wire Format Specification

## 1. Overview

This document specifies the binary format used to serialize a tuple of SQLite column values into a single BLOB. This format is used as the primary key representation in the `crsql_changes` virtual table (`pk` column).

**Purpose**: During replication, the `pk` blob is read from one database's `crsql_changes` and written to another. This makes the packed column format a **wire format** that must be bit-identical across all implementations.

**Functions**:
- `crsql_pack_columns(val1, val2, ...)` - encodes N SQLite values into a single BLOB
- `unpack_columns(blob)` - decodes a BLOB back into N SQLite values

## 2. Byte Layout

The packed format consists of:

```
+-------------+------------+------------+-----+------------+
| num_columns | column[0]  | column[1]  | ... | column[N-1]|
+-------------+------------+------------+-----+------------+
     1 byte      variable     variable          variable
```

**Header**:
- `num_columns`: 1 byte (`u8`) - the number of columns encoded
- Maximum 255 columns supported

**Per-column encoding**: Each column consists of:
```
+------------+------------------+---------+
| type_byte  | length (if any)  | payload |
+------------+------------------+---------+
   1 byte       0-8 bytes        variable
```

## 3. Type Byte Encoding

The type byte packs two pieces of information:

```
+---+---+---+---+---+---+---+---+
| 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
+---+---+---+---+---+---+---+---+
|     intlen      |    type     |
+-----------------+-------------+
     5 bits           3 bits
```

- **Bits 0-2** (low 3 bits): Column type tag
- **Bits 3-7** (high 5 bits): `intlen` - number of bytes used for integer/length encoding

**Extraction formulas**:
- `type = type_byte & 0x07`
- `intlen = (type_byte >> 3) & 0x1F`

**Construction formula**:
- `type_byte = (intlen << 3) | type`

## 4. Type Tag Values

| Type    | Value | Description                    |
|---------|-------|--------------------------------|
| Integer | 1     | Signed 64-bit integer          |
| Float   | 2     | IEEE 754 double precision      |
| Text    | 3     | UTF-8 text (not validated)     |
| Blob    | 4     | Raw binary data                |
| Null    | 5     | SQL NULL                       |

**Note**: Values 0, 6, 7 are invalid type tags. A decoder encountering these values must reject the input.

## 5. Integer Encoding

Integers are encoded using a variable-length big-endian signed representation.

### 5.1 Determining Byte Length (Encoding)

The encoder determines the minimum number of bytes needed by checking which bytes are non-zero, starting from the most significant:

```
For i64 value:
  if (value & 0xFF00000000000000) != 0 → 8 bytes
  if (value & 0x00FF000000000000) != 0 → 7 bytes
  if (value & 0x0000FF0000000000) != 0 → 6 bytes
  if (value & 0x000000FF00000000) != 0 → 5 bytes
  if (value & 0x00000000FF000000) != 0 → 4 bytes
  if (value & 0x0000000000FF0000) != 0 → 3 bytes
  if (value & 0x000000000000FF00) != 0 → 2 bytes
  if (value & 0x00000000000000FF) != 0 → 1 byte
  otherwise → 0 bytes
```

**Important**: This algorithm operates on the raw bit pattern, not the absolute value. For negative numbers (which have high bits set due to two's complement), this typically results in 8 bytes.

### 5.2 Byte Order

Integers are encoded in **big-endian** (network byte order), most significant byte first.

### 5.3 Sign Extension (Decoding)

When decoding fewer than 8 bytes, the decoder must perform **sign extension**. The `bytes` crate's `get_int(len)` function reads `len` bytes as a big-endian signed integer with sign extension.

For a decoder implementation:
1. Read `intlen` bytes in big-endian order
2. If `intlen < 8` and the high bit of the first byte is set (negative), sign-extend to 64 bits

### 5.4 Encoded Format

```
+------------+----------------------+
| type_byte  | value (intlen bytes) |
+------------+----------------------+
   1 byte        0-8 bytes, big-endian
```

Where `type_byte = (intlen << 3) | 0x01`

### 5.5 Examples

| Value       | intlen | type_byte | Payload bytes (hex)      |
|-------------|--------|-----------|--------------------------|
| 0           | 0      | 0x01      | (none)                   |
| 12          | 1      | 0x09      | 0C                       |
| 255         | 1      | 0x09      | FF                       |
| 256         | 2      | 0x11      | 01 00                    |
| 10000000    | 4      | 0x21      | 00 98 96 80              |
| -1          | 8      | 0x41      | FF FF FF FF FF FF FF FF  |
| -2500000    | 8      | 0x41      | FF FF FF FF FF D9 DF C0  |

**Note on negative numbers**: Because the algorithm checks raw bit patterns, negative numbers (with high bits set) almost always require 8 bytes. The value `-1` is `0xFFFFFFFFFFFFFFFF` in two's complement, so byte 7 (the MSB) is non-zero.

## 6. Float Encoding

Floats are encoded as IEEE 754 double-precision (64-bit) in **big-endian** byte order.

```
+------------+--------------------+
| type_byte  | value (8 bytes)    |
+------------+--------------------+
   1 byte      8 bytes, big-endian
```

- `type_byte = 0x02` (Float type, intlen is ignored/zero)
- Payload is always exactly 8 bytes

The `bytes` crate's `put_f64()` and `get_f64()` use big-endian byte order.

### 6.1 Examples

| Value  | type_byte | Payload bytes (hex)           |
|--------|-----------|-------------------------------|
| 0.0    | 0x02      | 00 00 00 00 00 00 00 00       |
| 1.0    | 0x02      | 3F F0 00 00 00 00 00 00       |
| -1.0   | 0x02      | BF F0 00 00 00 00 00 00       |
| NaN    | 0x02      | 7F F8 00 00 00 00 00 00       |
| +Inf   | 0x02      | 7F F0 00 00 00 00 00 00       |
| -Inf   | 0x02      | FF F0 00 00 00 00 00 00       |

## 7. Text Encoding

Text is encoded as a length-prefixed byte sequence.

```
+------------+---------------------+-----------------+
| type_byte  | length (intlen)     | UTF-8 bytes     |
+------------+---------------------+-----------------+
   1 byte      1-4 bytes, signed     length bytes
```

### 7.1 Length Encoding

The length is the byte count (not character count) of the UTF-8 text, encoded as a big-endian signed integer using the minimum necessary bytes:

```
For length (i32):
  if (length & 0xFF000000) != 0 → 4 bytes
  if (length & 0x00FF0000) != 0 → 3 bytes
  if (length & 0x0000FF00) != 0 → 2 bytes
  if (length & 0x000000FF) != 0 → 1 byte
  otherwise → 0 bytes
```

Note: There appears to be a bug in the reference implementation where `val * 0x000000FF` is used instead of `val & 0x000000FF` for the last check. The multiplication causes incorrect behavior for length=0, resulting in 0 bytes for length. This is documented here for compatibility.

### 7.2 Type Byte Construction

`type_byte = (intlen << 3) | 0x03`

### 7.3 UTF-8 Validation

**The encoder does NOT validate UTF-8**. It writes raw bytes from SQLite's `sqlite3_value_blob()`.

**The decoder uses `from_utf8_unchecked`** in Rust, meaning it does NOT validate UTF-8. A Zig implementation should match this permissive behavior for wire compatibility, or document any deviation.

### 7.4 Examples

| Text    | Length | intlen | type_byte | Length bytes | Payload          |
|---------|--------|--------|-----------|--------------|------------------|
| ""      | 0      | 0      | 0x03      | (none)       | (none)           |
| "str"   | 3      | 1      | 0x0B      | 03           | 73 74 72         |
| "hello" | 5      | 1      | 0x0B      | 05           | 68 65 6C 6C 6F   |

## 8. Blob Encoding

Blob encoding is identical to Text encoding, except for the type tag.

```
+------------+---------------------+-----------------+
| type_byte  | length (intlen)     | raw bytes       |
+------------+---------------------+-----------------+
   1 byte      1-4 bytes, signed     length bytes
```

### 8.1 Type Byte Construction

`type_byte = (intlen << 3) | 0x04`

### 8.2 Examples

| Blob (hex) | Length | intlen | type_byte | Length bytes | Payload    |
|------------|--------|--------|-----------|--------------|------------|
| (empty)    | 0      | 0      | 0x04      | (none)       | (none)     |
| 01 02 03   | 3      | 1      | 0x0C      | 03           | 01 02 03   |

## 9. NULL Encoding

NULL is encoded as just a type byte with no payload.

```
+------------+
| type_byte  |
+------------+
   1 byte
```

- `type_byte = 0x05` (Null type, intlen is 0)

No payload follows.

## 10. Complete Example

Encoding the tuple `(12, "str", x'010203')`:

```
Hex: 03 09 0C 0B 03 73 74 72 0C 03 01 02 03
     │  │  │  │  │  └─────┘  │  │  └─────┘
     │  │  │  │  │     │     │  │     │
     │  │  │  │  │     │     │  │     └── blob payload: 01 02 03
     │  │  │  │  │     │     │  └── blob length: 3
     │  │  │  │  │     │     └── type_byte: 0x0C = (1<<3)|4 = Blob, intlen=1
     │  │  │  │  │     └── text payload: "str" (73 74 72)
     │  │  │  │  └── text length: 3
     │  │  │  └── type_byte: 0x0B = (1<<3)|3 = Text, intlen=1
     │  │  └── integer payload: 12 (0x0C)
     │  └── type_byte: 0x09 = (1<<3)|1 = Integer, intlen=1
     └── num_columns: 3
```

Total: 13 bytes

## 11. Edge Cases

### 11.1 Zero Integer
- Value `0` encodes with `intlen=0`
- type_byte: `0x01`
- No payload bytes
- Total: 1 byte

### 11.2 Empty Text/Blob
- Length `0` encodes with `intlen=0` (due to the multiplication bug in length calculation)
- type_byte: `0x03` (Text) or `0x04` (Blob)
- No length bytes, no payload bytes
- Total: 1 byte

### 11.3 Negative Integers
- Due to two's complement and bit-checking from MSB, negative integers typically require 8 bytes
- Example: `-1` → intlen=8, payload=`FF FF FF FF FF FF FF FF`

### 11.4 Maximum Values
- `i64::MAX` (9223372036854775807) → intlen=8, payload=`7F FF FF FF FF FF FF FF`
- `i64::MIN` (-9223372036854775808) → intlen=8, payload=`80 00 00 00 00 00 00 00`

### 11.5 Maximum Columns
- Maximum 255 columns per packed value (limited by u8 column count)

### 11.6 Maximum Text/Blob Length
- Length is encoded as `i32`, maximum 2,147,483,647 bytes
- However, SQLite's practical blob limit is typically 1GB by default

### 11.7 Special Float Values
- NaN, +Infinity, -Infinity are encoded as their IEEE 754 bit patterns
- Negative zero (`-0.0`) has distinct encoding from positive zero

### 11.8 Truncated Input (Decoding)
- If input is truncated mid-column, decoder must return an error
- Check `remaining() >= intlen` before reading length
- Check `remaining() >= len` before reading payload

## 12. Wire Format Stability

**Critical**: This format has NO version byte. Any change to the encoding breaks interoperability with existing databases.

Implementations MUST:
1. Match byte output exactly for the same input values
2. Accept any valid encoding from other implementations
3. Not add extensions, version markers, or checksums

The canonical test vector is:
```
Input: (12, "str", x'010203')
Output: 03 09 0C 0B 03 73 74 72 0C 03 01 02 03
```

Any implementation that does not produce this exact output for this input is **incompatible**.

## 13. Decoder Error Conditions

A decoder must return an error for:
1. Truncated input (not enough bytes for declared column count)
2. Invalid type tag (0, 6, or 7)
3. Length exceeds remaining bytes
4. Float column with fewer than 8 remaining bytes

A decoder must NOT error for:
1. Invalid UTF-8 in Text columns (pass through as-is)
2. Unusual float values (NaN, Inf)

## 14. Implementation Notes

### 14.1 For Encoders
- Use `sqlite3_value_blob()` for both Text and Blob to get raw bytes
- Use `sqlite3_value_bytes()` to get length
- For integers, cast to signed before applying byte-count algorithm

### 14.2 For Decoders  
- Sign-extend integers when reading fewer than 8 bytes
- For Text, use unchecked UTF-8 conversion or pass raw bytes
- Allocate exact sizes after reading length prefix

### 14.3 Endianness Summary
- **Big-endian**: integers, lengths, floats
- All multi-byte values are network byte order
