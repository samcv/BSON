use v6;

use BSON::ObjectId;
use BSON::Regex;
use BSON::Javascript;
use BSON::Binary;
use BSON::Exception;

package BSON {

  #-----------------------------------------------------------------------------
  # BSON type codes
  #
  constant C-DOUBLE             = 0x01;
  constant C-STRING             = 0x02;
  constant C-DOCUMENT           = 0x03;
  constant C-ARRAY              = 0x04;
  constant C-BINARY             = 0x05;
  constant C-UNDEFINED          = 0x06;         # Deprecated
  constant C-OBJECTID           = 0x07;
  constant C-BOOLEAN            = 0x08;
  constant C-DATETIME           = 0x09;
  constant C-NULL               = 0x0A;
  constant C-REGEX              = 0x0B;
  constant C-DBPOINTER          = 0x0C;         # Deprecated
  constant C-JAVASCRIPT         = 0x0D;
  constant C-DEPRECATED         = 0x0E;         # Deprecated
  constant C-JAVASCRIPT-SCOPE   = 0x0F;
  constant C-INT32              = 0x10;
  constant C-TIMESTAMP          = 0x11;
  constant C-INT64              = 0x12;
  constant C-MIN-KEY            = 0xFF;
  constant C-MAX-KEY            = 0x7F;

  #-----------------------------------------------------------------------------
  # Fixed sizes
  #
  constant C-INT32-SIZE         = 4;
  constant C-INT64-SIZE         = 8;
  constant C-DOUBLE-SIZE        = 8;

  #-----------------------------------------------------------------------------
  class Document does Associative does Positional {

    subset Index of Int where $_ >= 0;

    has Str @!keys;
    has Hash $!data .= new;

    has Buf $!encoded-document;
    has Buf @!encoded-entries;
    has Index $!index = 0;


    # Encoded turns
    # 1) True on init, no need to 'await' promises.
    # 2) False on insert, delete or modify an entry
    # 3) True on encode() and decode()
    #
    has Bool $!encoded;
    has $!start-enc-time;
#    has Bool $!promises-wait;

    # Decoded turns
    # 1) False on init
    # 2) False on loading into $!encoded-document
    # 3) True on encode() and decode()
    #
    has Bool $!decoded;
    has $!start-dec-time;

    has Promise %!promises;

    #---------------------------------------------------------------------------
    #
    method new ( *@ps ) {
#say "PM: ", @ps.WHAT;
      self.bless(:pairs(@ps));
    }

    submethod BUILD (:@pairs!) {

      $!encoded = True;
      $!decoded = False;
      $!start-enc-time = now;
#      $!bson .= new;

      # self{x} = y will end up at ASSIGN-KEY
      #
      for @pairs -> $pair {
        self{$pair.key} = $pair.value;
      }
    }

    #---------------------------------------------------------------------------
    # Associative role methods
    #---------------------------------------------------------------------------
    method AT-KEY ( Str $key --> Any ) {

      $!data{$key}:exists ?? $!data{$key} !! Any;
    }

    #---------------------------------------------------------------------------
    method EXISTS-KEY ( Str $key --> Bool ) {

      return $!data{$key}:exists;
    }

    #---------------------------------------------------------------------------
    method DELETE-KEY ( Str $key --> Any ) {

      my $value;
      if $!data{$key}:exists {
        loop ( my $i = 0; $i < @!keys.elems; $i++ ) {
          if @!keys[$i] ~~ $key {
            @!keys.splice( $i, 1);
#say "Key = $key, i = $i, #ee: {@!encoded-entries.elems}";
            @!encoded-entries.splice( $i, 1) if @!encoded-entries.elems;   # $!encoded kept to True!
            $value = $!data{$key}:delete;
            last;
          }
        }
      }

      $value;
    }

    #---------------------------------------------------------------------------
#`{{
    multi method ASSIGN-KEY ( Str:D $key, Document:D $new) {

say "Asign-key($?LINE): $key => ", $new.WHAT;
      @!keys.push($key) unless $!data{$key}:exists;
      $!data{$key} = $new;

      %!promises{$key}:delete if %!promises{$key}:exists;

      my $k = $key;
      my $d := $!data{$key};
#      %!promises{$key} = Promise.start( {
          my Buf $b = self!encode-element: ($k => $d);
say "E: {now - $!start-enc-time} Done $k";
          $b;
#        }
#      );

      $!encoded = False;
    }
}}

    multi method ASSIGN-KEY ( Str:D $key, List:D $new) {

say "Asign-key($?LINE): $key => ", $new.WHAT;
      @!keys.push($key) unless $!data{$key}:exists;
      $!data{$key} = BSON::Document.new(|$new);

      %!promises{$key}:delete if %!promises{$key}:exists;

      my $k = $key;
      my $d := $!data{$key};
      %!promises{$key} = Promise.start( {
          my Buf $b = self!encode-element: ($k => $d);
#say "E: {now - $!start-enc-time} Done $k";
          $b;
        }
      );

      $!encoded = False;
    }

#`{{
    multi method ASSIGN-KEY ( Str:D $key, Pair:D $new) {

say "Asign-key($?LINE): $key => ", $new.WHAT;

      @!keys.push($key) unless $!data{$key}:exists;
      $!data{$key} = BSON::Document.new($new);

      %!promises{$key}:delete if %!promises{$key}:exists;

      my $k = $key;
      my $d := $!data{$key};
say "KV: $k => $d";
#      %!promises{$key} = Promise.start( {
          my Buf $b = self!encode-element: ($k => $d);
say "E: {now - $!start-enc-time} Done $k";
          $b;
#        }
#      );

      $!encoded = False;
    }
}}

    multi method ASSIGN-KEY ( Str:D $key, Any:D $new) {

say "Asign-key($?LINE): $key => ", $new.WHAT;

      @!keys.push($key) unless $!data{$key}:exists;
      $!data{$key} = $new;

      %!promises{$key}:delete if %!promises{$key}:exists;

      my $k = $key;
      my $d := $!data{$key};
      %!promises{$key} = Promise.start( {
          my Buf $b = self!encode-element: ($k => $d);
#say "B: $k => $d == ", $b;
#say "E: {now - $!start-enc-time} Done $k";
          $b;
        }
      );

      $!encoded = False;
    }

    #---------------------------------------------------------------------------
#`{{
Cannot use binding because when value changes the object cannot know that the
location is changed. This is nessesary to encode the key, value pair.
}}
    method BIND-KEY ( Str $key, \new ) {

      die "Cannot use binding";
#      $!data{$key} := new;
    }


    #---------------------------------------------------------------------------
    # Positional role methods
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    method AT-POS ( Index $idx --> Any ) {

      $idx < @!keys.elems ?? $!data{@!keys[$idx]} !! Any;
    }

    #---------------------------------------------------------------------------
    method EXISTS-POS ( Index $idx --> Bool ) {

      $idx < @!keys.elems;
    }

    #---------------------------------------------------------------------------
    method DELETE-POS ( Index $idx --> Any ) {

      $idx < @!keys.elems ?? (self{@!keys[$idx]}:delete) !! Nil;
    }

    #---------------------------------------------------------------------------
    method ASSIGN-POS ( Index $idx, $new! ) {
say "AP: $idx, $new";

      # If index is at a higher position then the last one then only
      # one place extended with a generated key na,e such as key21 on the
      # 21st location. Furthermore when a key like key21 has been used before
      # the array is not extended but the key location is used instead.
      #
      my $key = $idx >= @!keys.elems ?? 'key' ~ $idx !! @!keys[$idx];

      @!keys.push($key) unless $!data{$key}:exists;
      $!data{$key} = $new;

      %!promises{$key}:delete if %!promises{$key}:exists;
      %!promises{$key} = Promise.start( {
          self!encode-element: ($key => $!data{$key});
        }
      );

      $!encoded = False;
    }

    #---------------------------------------------------------------------------
#`{{
Cannot use binding because when value changes the object cannot know that the
location is changed. This is nessesary to encode the key, value pair.
}}
    method BIND-POS ( Index $idx, \new ) {

      die "Cannot use binding";
#      my $key = $idx >= @!keys.elems ?? 'key' ~ $idx !! @!keys[$idx];
#      $!data{$key} := new;
    }

    #---------------------------------------------------------------------------
    # Must be defined because of Positional and Associative sources of of()
    #---------------------------------------------------------------------------
    method of ( ) {
      Mu;
    }

    #---------------------------------------------------------------------------
    # And some extra methods
    #---------------------------------------------------------------------------
    method elems ( --> Int ) {

      @!keys.elems;
    }

    method kv ( --> List ) {

      my @l;
      for @!keys -> $k {
        @l.push( $k, $!data{$k});
      }

      @l;
    }

    #---------------------------------------------------------------------------
    method keys ( --> List ) {

      @!keys.list;
    }

    #---------------------------------------------------------------------------
    method values ( --> List ) {

      $!data{@!keys[*]}.list;
    }

    #---------------------------------------------------------------------------
    # Encoding document
    #---------------------------------------------------------------------------
    # Called from user to get encoded document
    #
    method encode ( --> Buf ) {
#say "Encode0: {self}, $!encoded";

      if ! ? $!encoded {
#say "Encode1: {@!keys.elems}";
        loop ( my $idx = 0; $idx < @!keys.elems; $idx++) {
          my $key = @!keys[$idx];
#say "Encode2: $key, {%!promises{$key}:exists}";
          if %!promises{$key}:exists {
            try {
              @!encoded-entries[$idx] = await %!promises{$key};

              CATCH {
                default {
                  say $_;
                }
              }
            }
          }

#say "Encode3: $idx, $key, ", @!encoded-entries[$idx];
        }

        $!encoded = True;
        %!promises = ();
#say "Encode4: $!encoded, {@!keys.elems}";
      }

      $!encoded-document = [~] @!encoded-entries;

      my Buf $b = [~] encode-int32($!encoded-document.elems + 5),
          $!encoded-document,
          Buf.new(0x00);

#say "Encode5: $!encoded, ", $b;
      return $b;
    }

    #---------------------------------------------------------------------------
    method !encode-document ( Pair:D @p --> Buf ) {
      my Buf $b = self!encode-e-list(@p);
      return [~] encode-int32($b.elems + 5), $b, Buf.new(0x00);
    }

    #---------------------------------------------------------------------------
    method !encode-e-list ( Pair:D @p --> Buf ) {
      my Buf $b = Buf.new();

      for @p -> $p {
        $b ~= self!encode-element($p);
      }

      return $b;
    }

    #---------------------------------------------------------------------------
    # Encode a key value pair. Called from the insertion methods above when a
    # key value pair is inserted.
    #
    # element ::= type-code e_name some-encoding
    #
    method !encode-element ( Pair:D $p --> Buf ) {

#say "EE: {$p.key} => {$p.value}, {$p.perl}";
      given $p.value {

        when Num {
          # Double precision
          # "\x01" e_name Num
          #
          return [~] Buf.new(C-DOUBLE),
                     encode-e-name($p.key),
                     self!encode-double($p.value);
        }

        when Str {
          # UTF-8 string
          # "\x02" e_name string
          #
          return [~] Buf.new(C-STRING),
                     encode-e-name($p.key),
                     encode-string($p.value)
                     ;
        }

        # Converting a pair same way as a hash:
        #
        when Pair {
          # Embedded document
          # "\x03" e_name document
          #
          my Pair @pairs = $p.value;
          return [~] Buf.new(C-DOCUMENT),
                     encode-e-name($p.key),
                     self!encode-document(@pairs)
                     ;
        }

        when Hash {
          # Embedded document
          # "\x03" e_name document
          #
          return [~] Buf.new(C-DOCUMENT),
                     encode-e-name($p.key),
                     self!encode-document($p.value)
                     ;
        }

        when BSON::Document {
          # Embedded document
          # "\x03" e_name document
          #
#say "Document: ", $p.key, ' => ', .keys;

          return [~] Buf.new(C-DOCUMENT),
                     encode-e-name($p.key),
                     .encode
                     ;
        }

        when Array {
          # Array
          # "\x04" e_name document

          # The document for an array is a normal BSON document
          # with integer values for the keys,
          # starting with 0 and continuing sequentially.
          # For example, the array ['red', 'blue']
          # would be encoded as the document {'0': 'red', '1': 'blue'}.
          # The keys must be in ascending numerical order.
          #
          # Simple assigning .kv to %hash wouldn't work because the order
          # of items can go wrong. Mongo doesn't process it very well if e.g.
          # { 1 => 'abc', 0 => 'def' } was encoded instead of
          # { 0 => 'def', 1 => 'abc' }.
          #
          my Pair @pairs;
          for .kv -> $k, $v {
            @pairs.push: ($k => $v);
          }

          return [~] Buf.new(C-ARRAY),
                     encode-e-name($p.key),
                     self!encode-document(@pairs)
                     ;
        }

        when BSON::Binary {
          # Binary data
          # "\x05" e_name int32 subtype byte*
          # subtype is '\x00' for the moment (Generic binary subtype)
          #
          my Buf $b = [~] Buf.new(C-BINARY), encode-e-name($p.key);

          if .has-binary-data {
            $b ~= encode-int32(.binary-data.elems);
            $b ~= Buf.new(.binary-type);
            $b ~= .binary-data;
          }

          else {
            $b ~= encode-int32(0);
            $b ~= Buf.new(.binary-type);
          }

          $b;
        }

#`{{
        # Do not know what type to test. Any, Nil?
        when Any {
          # Undefined deprecated 
          # "\x06" e_name
          #
          die X::BSON::Deprecated.new(
            operation => 'encode',
            type => 'Undefined(0x06)'
          );
        }
}}
        when BSON::ObjectId {
          # ObjectId
          # "\x07" e_name (byte*12)
          #
          return Buf.new(C-OBJECTID) ~ encode-e-name($p.key) ~ .Buf;
        }

        when Bool {
          # Bool
          # \0x08 e_name (\0x00 or \0x01)
          #
          if .Bool {
            # Boolean "true"
            # "\x08" e_name "\x01
            #
            return Buf.new(C-BOOLEAN) ~ encode-e-name($p.key) ~ Buf.new(0x01);
          }
          else {
            # Boolean "false"
            # "\x08" e_name "\x00
            #
            return Buf.new(C-BOOLEAN) ~ encode-e-name($p.key) ~ Buf.new(0x00);
          }
        }

        when DateTime {
          # UTC dateime
          # "\x09" e_name int64
          #
          return [~] Buf.new(C-DATETIME),
                     encode-e-name($p.key),
                     encode-int64($p.value().posix())
                     ;
        }

        when not .defined {
          # Null value
          # "\x0A" e_name
          #
          return Buf.new(C-NULL) ~ encode-e-name($p.key);
        }

        when BSON::Regex {
          # Regular expression
          # "\x0B" e_name cstring cstring
          #
          return [~] Buf.new(C-REGEX),
                     encode-e-name($p.key),
                     encode-cstring($p.value.regex),
                     encode-cstring($p.value.options)
                     ;
        }

#`{{
        when ... {
          # DBPointer - deprecated
          # "\x0C" e_name string (byte*12)
          #
          die X::BSON::Deprecated(
            operation => 'encoding DBPointer',
            type => '0x0C'
          );
        }
}}

        # This entry does 2 codes. 0x0D for javascript only and 0x0F when
        # there is a scope document defined in the object
        #
        when BSON::Javascript {

#          return .encode-javascript( $p.key, self);
#`{{}}
          # Javascript code
          # "\x0D" e_name string
          # "\x0F" e_name int32 string document
          #
          if .has-javascript {
            my Buf $js = encode-string(.javascript);

            if .has-scope {
              my Buf $doc = .scope.encode;
#say "JS Doc: ", $doc;
              return [~] Buf.new(C-JAVASCRIPT-SCOPE),
                         encode-e-name($p.key),
#                         encode-int32([+] $js.elems, $doc.elems, 4),
                         $js, $doc
                         ;
            }

            else {
              return [~] Buf.new(C-JAVASCRIPT), encode-e-name($p.key), $js;
            }
          }

          else {
            die X::BSON::ImProperUse.new( :operation('encode'),
                                          :type('javascript 0x0D/0x0F'),
                                          :emsg('cannot send empty code')
                                        );
          }

        }

#`{{
        when ... {
          # ? - deprecated
          # "\x0E" e_name string (byte*12)
          #
          die X::BSON::Deprecated(
            operation => 'encoding ?',
            type => '0x0E'
          );
        }

        when ... {
          # Javascript code with scope. Handled above.
          # "\x0F" e_name string document
        }
}}

        when Int {
          # Integer
          # "\x10" e_name int32
          # '\x12' e_name int64
          #
          if -0xffffffff < $p.value < 0xffffffff {
            return [~] Buf.new(C-INT32),
                       encode-e-name($p.key),
                       encode-int32($p.value)
                       ;
          }

          elsif -0x7fffffff_ffffffff < $p.value < 0x7fffffff_ffffffff {
            return [~] Buf.new(C-INT64),
                       encode-e-name($p.key),
                       encode-int64($p.value)
                       ;
          }

          else {
            my $reason = 'small' if $p.value < -0x7fffffff_ffffffff;
            $reason = 'large' if $p.value > 0x7fffffff_ffffffff;
            die X::BSON::ImProperUse.new( :operation('encode'),
                                          :type('integer 0x10/0x12'),
                                          :emsg("cannot encode too $reason number")
                                        );
          }
        }

#`{{
        when ... {
            # Timestamp. 
            # "\x11" e_name int64
            #
            # Special internal type used by MongoDB replication and
            # sharding. First 4 bytes are an increment, second 4 are a
            # timestamp.
        }
}}

        # Buf is converted to BSON binary with generic type. When decoding it
        # will always be BSON::Binary again. Buf can be retrieved with
        # $o.binary-data;
        #
        when Buf {
          my BSON::Binary $bbin .= new(:data($_));
          my Buf $b = [~] Buf.new(C-BINARY), encode-e-name($p.key);
          $b ~= encode-int32(.binary-data.elems);
          $b ~= Buf.new(.binary-type);
          $b ~= .binary-data;

          $b;
        }

        default {
          if .can('encode') and .can('bson-code') {
            my $code = .bson-code;

            return [~] Buf.new($code),
                       encode-e-name($p.key),
                       .encode;
          }

          else {
            die X::BSON::NYS.new(
              :operation('encode'),
              :type($_ ~ '(' ~ ($_.^name // 'Unknown') ~ ')')
            );
          }
        }
      }
    }

    #---------------------------------------------------------------------------
    sub encode-e-name ( Str:D $s --> Buf ) {
      return encode-cstring($s);
    }

    #---------------------------------------------------------------------------
    sub encode-cstring ( Str:D $s --> Buf ) {
      die X::BSON::Parse.new(
        :operation('encode-cstring'),
        :error('Forbidden 0x00 sequence in $s')
      ) if $s ~~ /\x00/;

      return $s.encode() ~ Buf.new(0x00);
    }

    #---------------------------------------------------------------------------
    sub encode-string ( Str:D $s --> Buf ) {
      my Buf $b .= new($s.encode('UTF-8'));
      return [~] encode-int32($b.bytes + 1), $b, Buf.new(0x00);
    }

    #---------------------------------------------------------------------------
    sub encode-int32 ( Int:D $i ) {
      my int $ni = $i;      
      return Buf.new( $ni +& 0xFF, ($ni +> 0x08) +& 0xFF,
                      ($ni +> 0x10) +& 0xFF, ($ni +> 0x18) +& 0xFF
                    );
    }

    #---------------------------------------------------------------------------
    sub encode-int64 ( Int:D $i ) {
      # No tests for too large/small numbers because it is called from
      # _enc_element normally where it is checked
      #
      my int $ni = $i;
      return Buf.new( $ni +& 0xFF, ($ni +> 0x08) +& 0xFF,
                      ($ni +> 0x10) +& 0xFF, ($ni +> 0x18) +& 0xFF,
                      ($ni +> 0x20) +& 0xFF, ($ni +> 0x28) +& 0xFF,
                      ($ni +> 0x30) +& 0xFF, ($ni +> 0x38) +& 0xFF
                    );

      # Original method goes wrong on negative numbers. Also modulo operations
      # are slower than the bit operations.
      #
      #return Buf.new( $i % 0x100, $i +> 0x08 % 0x100, $i +> 0x10 % 0x100,
      #                $i +> 0x18 % 0x100, $i +> 0x20 % 0x100,
      #                $i +> 0x28 % 0x100, $i +> 0x30 % 0x100,
      #                $i +> 0x38 % 0x100
      #              );
    }

    #---------------------------------------------------------------------------
    method !encode-double ( Num:D $r is copy --> Buf ) {

      # Make array starting with bson code 0x01 and the key name
      my Buf $a = Buf.new(); # Buf.new(0x01) ~ encode-e-name($key-name);
      my Num $r2;

      # Test special cases
      #
      # 0x 0000 0000 0000 0000 = 0
      # 0x 8000 0000 0000 0000 = -0       Not recognizable
      # 0x 7ff0 0000 0000 0000 = Inf
      # 0x fff0 0000 0000 0000 = -Inf
      # 0x 7ff0 0000 0000 0001 <= nan <= 0x 7ff7 ffff ffff ffff signalling NaN
      # 0x fff0 0000 0000 0001 <= nan <= 0x fff7 ffff ffff ffff
      # 0x 7ff8 0000 0000 0000 <= nan <= 0x 7fff ffff ffff ffff quiet NaN
      # 0x fff8 0000 0000 0000 <= nan <= 0x ffff ffff ffff ffff
      #
      given $r {
        when 0.0 {
          $a ~= Buf.new(0 xx 8);
        }

        when -Inf {
          $a ~= Buf.new( 0 xx 6, 0xF0, 0xFF);
        }

        when Inf {
          $a ~= Buf.new( 0 xx 6, 0xF0, 0x7F);
        }

        when NaN {
          # Choose only one number out of the quiet NaN range
          #
          $a ~= Buf.new( 0 xx 6, 0xF8, 0x7F);
        }

        default {
          my Int $sign = $r.sign == -1 ?? -1 !! 1;
          $r *= $sign;

          # Get proper precision from base(2). Adjust the exponent bias for
          # this.
          #
          my Int $exp-shift = 0;
          my Int $exponent = 1023;
          my Str $bit-string = $r.base(2);

          $bit-string ~= '.' unless $bit-string ~~ m/\./;

          # Smaller than one
          #
          if $bit-string ~~ m/^0\./ {

            # Normalize, Check if a '1' is found. Possible situation is
            # a series of zeros because r.base(2) won't give that much
            # information.
            #
            my $first-one;
            while !($first-one = $bit-string.index('1')) {
              $exponent -= 52;
              $r *= 2 ** 52;
              $bit-string = $r.base(2);
            }

            $first-one--;
            $exponent -= $first-one;

            $r *= 2 ** $first-one;                # 1.***
            $r2 = $r * 2 ** 52;                   # Get max precision
            $bit-string = $r2.base(2);            # Get bits
            $bit-string ~~ s/\.//;                # Remove dot
            $bit-string ~~ s/^1//;                # Remove first 1
          }

          # Bigger than one
          #
          else {
            # Normalize
            #
            my Int $dot-loc = $bit-string.index('.');
            $exponent += ($dot-loc - 1);

            # If dot is in the string, not at the end, the precision might
            # be not sufficient. Enlarge one time more
            #
            my Int $str-len = $bit-string.chars;
            if $dot-loc < $str-len - 1 or $str-len < 52 {
              $r2 = $r * 2 ** 52;                 # Get max precision
              $bit-string = $r2.base(2);          # Get bits
            }

            $bit-string ~~ s/\.//;              # Remove dot
            $bit-string ~~ s/^1//;              # Remove first 1
          }

          # Prepare the number. First set the sign bit.
          #
          my Int $i = $sign == -1 ?? 0x8000_0000_0000_0000 !! 0;

          # Now fit the exponent on its place
          #
          $i +|= $exponent +< 52;

          # And the precision
          #
          $i +|= :2($bit-string.substr( 0, 52));

          $a ~= encode-int64($i);
        }
      }

      return $a;
    }

    #---------------------------------------------------------------------------
    # Decoding document
    #---------------------------------------------------------------------------
    method decode ( Buf $data --> Nil ) {

      $!encoded-document = $data;
      $!encoded = True;
      $!decoded = False;

      @!keys = ();
      $!data .= new;

      # Document decoding start: init index
      #
      $!index = 0;
      $!start-dec-time = now;

      # Decode the document, then wait for any started parallel tracks
      #
      self!decode-document;
      if %!promises.elems {
        try {
          await %!promises.values;

          CATCH {
            default {
              say $_;
            }
          }
        }
      }
    }

    #---------------------------------------------------------------------------
    method !decode-document ( --> Nil ) {

say "DE 0 I: $!index";
      # Get the size of the (nested-)document
      #
      my Int $doc-size = decode-int32( $!encoded-document, $!index);
      $!index += C-INT32-SIZE;
say "DE 1 I: $!index, $doc-size, ", $!encoded-document;

      while $!encoded-document[$!index] !~~ 0x00 {
say "DE 2 I: $!index, $doc-size";
        self!decode-element;
      }
say "DE 3 I: $!index, $doc-size";

      # Check size of document with final byte location
      #
      die "Size of document $doc-size does not match with index at $!index(+1)"
        if $doc-size != $!index + 1;
    }

    #---------------------------------------------------------------------------
    method !decode-element ( --> Nil ) {

      # Get the value type of next pair
      #
      my $bson-code = $!encoded-document[$!index++];

      # Get the key value, Index is adjusted to just after the 0x00
      # of the string.
      #
      my Str $key = decode-e-name( $!encoded-document, $!index);

      # Keys are pushed in the proper order as they are seen in the
      # byte buffer.
      #
      @!keys.push($key);
      my Int $size;

      given $bson-code {

        # 64-bit floating point
        #
        when C-DOUBLE {

          my Int $i = $!index;
          $!index += C-DOUBLE-SIZE;
          %!promises{$key} = Promise.start( {
              $!data{$key} = self!decode-double( $!encoded-document, $i);
say "{now - $!start-dec-time} Done $key => $!data{$key}";
            }
          );
        }

        # Nested document
        #
        when C-DOCUMENT {

#say "Doc 0: $!index";
          my $i = $!index;
          my Int $doc-size = decode-int32( $!encoded-document, $i);
          $!index += $doc-size;
#say "Doc 1: $doc-size, $i, $!index, $!encoded-document[$!index]";
          %!promises{$key} = Promise.start( {
              my BSON::Document $d .= new;
              $d.decode(Buf.new($!encoded-document[$i ..^ ($i + $doc-size)]));
              $!data{$key} = $d;
say "{now - $!start-dec-time} Done $key => $!data{$key}";
            }
          );
        }

        # Binary code
        # "\x05 e_name int32 subtype byte*
        # subtype = byte \x00 .. \x05, .. \xFF
        # subtypes \x80 to \xFF are user defined
        #
        when C-BINARY {

          my Int $nbr-bytes = decode-int32( $!encoded-document, $!index);
          my $i = $!index + C-INT32-SIZE;

          # Step over size field, subtype and binary data
          #
          $!index += C-INT32-SIZE + 1 + $nbr-bytes;

          %!promises{$key} = Promise.start( {
              $!data{$key} = self!decode-binary(
                $!encoded-document,
                $i,
                $nbr-bytes
              );
            }
          );
        }

        # Boolean code
        #
        when C-BOOLEAN {

          my $i = $!index;
          $!index++;
          %!promises{$key} = Promise.start( {
              $!data{$key} = $!encoded-document[$i] ~~ 0x00 ?? False !! True;
            }
          );
        }

        # Javascript code
        #
        when C-JAVASCRIPT {

          # Get the size of the javascript code text, then adjust index
          # for this size and set i for the decoding. Then adjust index again
          # for the next action.
          #
          my Int $i = $!index;
          my Int $js-size = decode-int32( $!encoded-document, $i);

          # Step over size field and the javascript text
          #
          $!index += (C-INT32-SIZE + $js-size);

          %!promises{$key} = Promise.start( {
              $!data{$key} = BSON::Javascript.new(
                :javascript(decode-string( $!encoded-document, $i))
              );
say "{now - $!start-dec-time} Done $key => $!data{$key}";
            }
          );
        }

        # Javascript code with scope
        #
        when C-JAVASCRIPT-SCOPE {

          my Int $i1 = $!index;
          my Int $js-size = decode-int32( $!encoded-document, $i1);
          my Int $i2 = $!index + C-INT32-SIZE + $js-size;
          my Int $js-scope-size = decode-int32( $!encoded-document, $i2);

          $!index += (C-INT32-SIZE + $js-size + $js-scope-size);

          %!promises{$key} = Promise.start( {
              my BSON::Document $d .= new;
              $d.decode(Buf.new($!encoded-document[$i2 ..^ ($i2 + $js-size)]));
              $!data{$key} = BSON::Javascript.new(
                :javascript(decode-string( $!encoded-document, $i1)),
                :scope($d)
              );
say "{now - $!start-dec-time} Done $key => $!data{$key}";
            }
          );
        }

        # 32-bit Integer
        #
        when C-INT32 {

          my Int $i = $!index;
          $!index += C-INT32-SIZE;

          %!promises{$key} = Promise.start( {
              $!data{$key} = decode-int32( $!encoded-document, $i);
say "{now - $!start-dec-time} Done $key => $!data{$key}";
            }
          );
        }

        # 64-bit Integer
        #
        when C-INT64 {

          my Int $i = $!index;
          $!index += C-INT64-SIZE;

          %!promises{$key} = Promise.start( {
              $!data{$key} = decode-int64( $!encoded-document, $i);
say "{now - $!start-dec-time} Done $key => $!data{$key}";
            }
          );
        }

        default {
          # We must stop because we do not know what the length should be of
          # this particular structure.
          #
          die "BSON code '{.fmt('0x%02x')}' not supported";
        }
      }
    }

    #-----------------------------------------------------------------------------
    sub decode-e-name ( Buf:D $b, Int:D $index is rw --> Str ) {
      return decode-cstring( $b, $index);
    }

    #-----------------------------------------------------------------------------
    sub decode-cstring ( Buf:D $b, Int:D $index is rw --> Str ) {

      my @a;
      my $l = $b.elems;
#note "DCS: $index, $l, $b[$l]";
#      while $index < $l and $b[$index] !~~ 0x00 {
      while $b[$index] !~~ 0x00 and $index < $l {
        @a.push($b[$index++]);
      }

      die X::BSON::Parse.new(
        :operation<decode-cstring>,
        :error('Missing trailing 0x00')
      ) unless $index < $l and $b[$index++] ~~ 0x00;

      return Buf.new(@a).decode();
    }

    #-----------------------------------------------------------------------------
    sub decode-string ( Buf:D $b, Int:D $index is copy --> Str ) {

      my $size = decode-int32( $b, $index);

#say "\nDS0: {$b.elems} - $size >= $index, ", $b;
      my $end-string-at = $index + 4 + $size - 1;
#say "DS1: ", $b[$index+4].fmt('%02x'), ', ', $b[$end-string-at].fmt('%02x');

      # Check if there are enaugh letters left
      #
      die X::BSON::Parse.new(
        :operation<decode-string>,
        :error('Not enaugh characters left')
      ) unless ($b.elems - $size) > $index;

      die X::BSON::Parse.new(
        :operation<decode-string>,
        :error('Missing trailing 0x00')
      ) unless $b[$end-string-at] ~~ 0x00;

      return Buf.new($b[$index+4 ..^ $end-string-at]).decode;
    }

    #-----------------------------------------------------------------------------
    sub decode-int32 ( Buf:D $b, Int:D $index --> Int ) {

#say "i32 0: CF: ", callframe(1).file, ', ', callframe(1).line;
#say "i32 1: CF: $index, ", $b;

      # Check if there are enaugh letters left
      #
      die X::BSON::Parse.new(
        :operation<decode-int32>,
        :error('Not enaugh characters left')
      ) if $b.elems - $index < 4;

      my int $ni = $b[$index]             +| $b[$index + 1] +< 0x08 +|
                   $b[$index + 2] +< 0x10 +| $b[$index + 3] +< 0x18
                   ;

      # Test if most significant bit is set. If so, calculate two's complement
      # negative number.
      # Prefix +^: Coerces the argument to Int and does a bitwise negation on
      # the result, assuming two's complement. (See
      # http://doc.perl6.org/language/operators^)
      # Infix +^ :Coerces both arguments to Int and does a bitwise XOR
      # (exclusive OR) operation.
      #
      $ni = (0xffffffff +& (0xffffffff+^$ni) +1) * -1  if $ni +& 0x80000000;
      return $ni;
    }

    #-----------------------------------------------------------------------------
    sub decode-int64 ( Buf:D $b, Int:D $index --> Int ) {
      # Check if there are enaugh letters left
      #
      die X::BSON::Parse.new(
        :operation<decode-int64>,
        :error('Not enaugh characters left')
      ) if $b.elems - $index < 8;

      my int $ni = $b[$index]             +| $b[$index + 1] +< 0x08 +|
                   $b[$index + 2] +< 0x10 +| $b[$index + 3] +< 0x18 +|
                   $b[$index + 4] +< 0x20 +| $b[$index + 5] +< 0x28 +|
                   $b[$index + 6] +< 0x30 +| $b[$index + 7] +< 0x38
                   ;
      return $ni;
    }

    #---------------------------------------------------------------------------
    # We have to do some simulation using the information on
    # http://en.wikipedia.org/wiki/Double-precision_floating-point_format#Endianness
    # until better times come.
    #
    method !decode-double ( Buf:D $b, Int:D $index --> Num ) {

      # Test special cases
      #
      # 0x 0000 0000 0000 0000 = 0
      # 0x 8000 0000 0000 0000 = -0
      # 0x 7ff0 0000 0000 0000 = Inf
      # 0x fff0 0000 0000 0000 = -Inf
      # 0x 7ff0 0000 0000 0001 <= nan <= 0x 7ff7 ffff ffff ffff signalling NaN
      # 0x fff0 0000 0000 0001 <= nan <= 0x fff7 ffff ffff ffff
      # 0x 7ff8 0000 0000 0000 <= nan <= 0x 7ff7 ffff ffff ffff quiet NaN
      # 0x fff8 0000 0000 0000 <= nan <= 0x ffff ffff ffff ffff
      #
      my Bool $six-byte-zeros = True;
      for ^6 -> $i {
        if ? $b[$i] {
          $six-byte-zeros = False;
          last;
        }
      }

      my Num $value;
      if $six-byte-zeros and $b[6] == 0 {
        if $b[7] == 0 {
          $value .= new(0);
        }

        elsif $b[7] == 0x80 {
          $value .= new(-0);
        }
      }

      elsif $six-byte-zeros and $b[6] == 0xF0 {
        if $b[7] == 0x7F {
          $value .= new(Inf);
        }

        elsif $b[7] == 0xFF {
          $value .= new(-Inf);
        }
      }

      elsif $b[7] == 0x7F and (0xf0 <= $b[6] <= 0xf7 or 0xf8 <= $b[6] <= 0xff) {
        $value .= new(NaN);
      }

      elsif $b[7] == 0xFF and (0xf0 <= $b[6] <= 0xf7 or 0xf8 <= $b[6] <= 0xff) {
        $value .= new(NaN);
      }

      # If value is not set by the special cases above, calculate it here
      #
      if !$value.defined {

        my Int $i = decode-int64( $b, $index);
        my Int $sign = $i +& 0x8000_0000_0000_0000 ?? -1 !! 1;

        # Significand + implicit bit
        #
        my $significand = 0x10_0000_0000_0000 +| ($i +& 0xF_FFFF_FFFF_FFFF);

        # Exponent - bias (1023) - the number of bits for precision
        #
        my $exponent = (($i +& 0x7FF0_0000_0000_0000) +> 52) - 1023 - 52;

        $value = Num.new((2 ** $exponent) * $significand * $sign);
      }

      return $value;
    }

    #---------------------------------------------------------------------------
    method !decode-binary (
      Buf:D $b, Int:D $index is copy, Int:D $nbr-bytes
      --> BSON::Binary
    ) {

      # Get subtype
      #
      my $sub_type = $b[$index++];

      # Most of the tests are not necessary because of arbitrary sizes.
      # UUID and MD5 can be tested.
      #
      given $sub_type {
        when BSON::C-GENERIC {
          # Generic binary subtype
        }

        when BSON::C-FUNCTION {
          # Function
        }

        when BSON::C-BINARY-OLD {
          # Binary (Old - deprecated)
          die 'Code (0x02) Deprecated binary data';
        }

        when BSON::C-UUID-OLD {
          # UUID (Old - deprecated)
          die 'UUID(0x03) Deprecated binary data';
        }

        when BSON::C-UUID {
          # UUID. According to
          # http://en.wikipedia.org/wiki/Universally_unique_identifier the
          # universally unique identifier is a 128-bit (16 byte) value.
          #
          die 'UUID(0x04) Binary string parse error'
            unless $nbr-bytes ~~ BSON::C-UUID-SIZE;
        }

        when BSON::C-MD5 {
          # MD5. This is a 16 byte number (32 character hex string)
          die 'MD5(0x05) Binary string parse error'
            unless $nbr-bytes ~~ BSON::C-MD5-SIZE;
        }

        when 0x80 {
          # User defined. That is, all other codes 0x80 .. 0xFF
        }
      }

say "Bin: $index .. {$index + $nbr-bytes}";
      return BSON::Binary.new(
        :data(Buf.new($b[$index ..^ ($index + $nbr-bytes)])),
        :type($sub_type)
      );
    }
  }
}

