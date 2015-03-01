#!/usr/bin/env perl6
#
use v6;

#-------------------------------------------------------------------------------
#
role BSON::CString_Decoder {
  method decode_cstring ( Array $a ) {

      my @a;
      while $a[ 0 ] !~~ 0x00 {
          @a.push( $a.shift );
      }

      die 'Parse error' unless $a.shift ~~ 0x00;
      return Buf.new( @a ).decode();
  }
}

#-------------------------------------------------------------------------------
#
role BSON::Int32_Decoder {
  method decode_int32 ( Array $a --> Int ) {
      my int $ni = $a.shift +| $a.shift +< 0x08 +|
                   $a.shift +< 0x10 +| $a.shift +< 0x18
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

# Original method goes wrong on negative numbers. Also adding might be slower
# than the bit operations. 
# return [+] $a.shift, $a.shift +< 0x08, $a.shift +< 0x10, $a.shift +< 0x18;
  }
}

#-------------------------------------------------------------------------------
#
role BSON::Int64_Decoder {
  method decode_int64 ( Array $a --> Int ) {
      my int $ni = $a.shift +| $a.shift +< 0x08 +|
                   $a.shift +< 0x10 +| $a.shift +< 0x18 +|
                   $a.shift +< 0x20 +| $a.shift +< 0x28 +|
                   $a.shift +< 0x30 +| $a.shift +< 0x38
                   ;
      return $ni;
  }
}

#-------------------------------------------------------------------------------
#
role BSON::Double_Decoder {
  method decode_double ( Array $a --> Num ) {

      # Test special cases
      #
      # 0x 0000 0000 0000 0000 = 0
      # 0x 8000 0000 0000 0000 = -0
      # 0x 7ff0 0000 0000 0000 = Inf
      # 0x fff0 0000 0000 0000 = -Inf
      #
      my Bool $six-byte-zeros = True;
      for ^6 -> $i {
          if $a[$i] {
              $six-byte-zeros = False;
              last;
          }
      }

      my Num $value;
      if $six-byte-zeros and $a[6] == 0 {
          if $a[7] == 0 {
              $value .= new(0);
          }

          elsif $a[7] == 0x80 {
              $value .= new(-0);
          }
      }

      elsif $a[6] == 0xF0 {
          if $a[7] == 0x7F {
              $value .= new(Inf);
          }

          elsif $a[7] == 0xFF {
              $value .= new(-Inf);
          }
      }

      # If value is set by the special cases above, remove the 8 bytes from
      # the array.
      #
      if $value.defined {
          $a.splice( 0, 8);
      }

      # If value is not set by the special cases above, calculate it here
      #
      else {
        my Int $i = self.decode_int64( $a );
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
}

#-------------------------------------------------------------------------------
#
class BSON::Decoder {
  also does BSON::CString_Decoder;
  also does BSON::Int64_Decoder;
  also does BSON::Double_Decoder;

  constant $DOUBLE = 0x01;

  has Int $.code;
  has Str $.key;
  has Any $.value;

  method decode ( Array $a ) {
    self.decode_code($a);
    self.decode_key($a);

    given $!code {

      when $DOUBLE {
        $!value = self.decode_double($a);
#say "V: $!value";
      }
    }
  }

  method decode_code ( Array $a ) {
      $!code = $a.shift;
#say "C: $!code";
  }

  method decode_key ( Array $a ) {
      $!key = self.decode_cstring( $a );
#say "K: $!key";
  }
}
