use v6;
use Test;
use BSON::Document;
use BSON::Javascript;
use BSON::Binary;
use UUID;

#-------------------------------------------------------------------------------
subtest {

  my BSON::Javascript $js .= new(
    :javascript('function(x){return x;}')
  );

  my BSON::Javascript $js-scope .= new(
    :javascript('function(x){return x;}'),
    :scope(BSON::Document.new: (nn => 10, a1 => 2))
  );

  my UUID $uuid .= new(:version(4));
  my BSON::Binary $bin .= new(
    :data($uuid.Blob),
    :type(BSON::C-UUID)
  );

  # Tests of
  #
  # 0x01 Double
  # 0x03 Document
  # 0x05 Binary
  # 0x08 Boolean
  # 0x0D Javascript
  # 0x0F Javascript with scope
  # 0x10 int32
  # 0x12 int64
  #
  my BSON::Document $d .= new;

  # Filling with data
  #
  $d<b> = -203.345.Num;
  $d<a> = 1234;
  $d<v> = 4295392664;
  $d<w> = $js;
  $d<abcdef> = a1 => 10, bb => 11;
  $d<abcdef><b1> = q => 255;
  $d<jss> = $js-scope;
  $d<bin> = $bin;
  $d<bf> = False;
  $d<bt> = True;

say $d.encode;

  # Handcrafted encoded BSON data
  #
  my Buf $etst = Buf.new(
    # 198 (4 + 11 + 7 + 11 + 30 + 45 + 53 + 26 + 5 + 5 + 1)
    0xc6, 0x00, 0x00, 0x00,                     # Size document

    # 11
    BSON::C-DOUBLE,                             # 0x01
      0x62, 0x00,                               # 'b'
      0xd7, 0xa3, 0x70, 0x3d,                   # -203.345
      0x0a, 0x6b, 0x69, 0xc0,

    # 7
    BSON::C-INT32,                              # 0x10
      0x61, 0x00,                               # 'a'
      0xd2, 0x04, 0x00, 0x00,                   # 1234

    # 11
    BSON::C-INT64,                              # 0x12
      0x76, 0x00,                               # 'v'
      0x98, 0x7d, 0x06, 0x00,                   # 4295392664
      0x01, 0x00, 0x00, 0x00,

    # 30
    BSON::C-JAVASCRIPT,                         # 0x0D
      0x77, 0x00,                               # 'w'
      0x17, 0x00, 0x00, 0x00,                   # 23 bytes js code + 1
      0x66, 0x75, 0x6e, 0x63, 0x74, 0x69,       # UTF8 encoded Javascript
      0x6f, 0x6e, 0x28, 0x78, 0x29, 0x7b,       # 'function(x){return x;}'
      0x72, 0x65, 0x74, 0x75, 0x72, 0x6e,
      0x20, 0x78, 0x3b, 0x7d, 0x00,

    # 45 (37 + 8)
    BSON::C-DOCUMENT,                           # 0x03
      0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x00, # 'abcdef'

      # 37 (4 + 8 + 8 + 16 + 1)
      0x25, 0x00, 0x00, 0x00,                   # Size nested document

      # 8
      BSON::C-INT32,                            # 0x10
        0x61, 0x31, 0x00,                       # 'a1'
        0x0a, 0x00, 0x00, 0x00,                 # 10

      # 8
      BSON::C-INT32,                            # 0x10
        0x62, 0x62, 0x00,                       # 'bb'
        0x0b, 0x00, 0x00, 0x00,                 # 11

      # 16 (12 + 4)
      BSON::C-DOCUMENT,                         # 0x03
        0x62, 0x31, 0x00,                       # 'b1'

        # 12 (4 + 7 + 1)
        0x0c, 0x00, 0x00, 0x00,                 # Size nested document

        # 7
        BSON::C-INT32,                          # 0x10
          0x71, 0x00,                           # 'q'
          0xff, 0x00, 0x00, 0x00,               # 255

        0x00,                                   # End nested document

      0x00,                                     # End nested document

    # 53 (32 + 21)
    BSON::C-JAVASCRIPT-SCOPE,                   # 0x0F
      0x6a, 0x73, 0x73, 0x00,                   # 'jss'
      0x17, 0x00, 0x00, 0x00,                   # 23 bytes js code + 1
      0x66, 0x75, 0x6e, 0x63, 0x74, 0x69,       # UTF8 encoded Javascript
      0x6f, 0x6e, 0x28, 0x78, 0x29, 0x7b,       # 'function(x){return x;}'
      0x72, 0x65, 0x74, 0x75, 0x72, 0x6e,
      0x20, 0x78, 0x3b, 0x7d, 0x00,

      # 21                                      # No key encoded
                                                # No BSON::C-DOCUMENT# code

        # 21 (4 + 8 + 8 + 1)
        0x15, 0x00, 0x00, 0x00,                 # Size nested document

        # 8
        BSON::C-INT32,                          # 0x10
          0x6e, 0x6e, 0x00,                     # 'nn'
          0x0a, 0x00, 0x00, 0x00,               # 10

        # 8
        BSON::C-INT32,                          # 0x10
          0x61, 0x31, 0x00,                     # 'a1'
          0x02, 0x00, 0x00, 0x00,               # 2

        0x00,                                   # End nested document

    # 26
    BSON::C-BINARY,                             # 0x05
      0x62, 0x69, 0x6e, 0x00,                   # 'bin'
      BSON::C-UUID-SIZE, 0x00, 0x00, 0x00,      # UUID size
      BSON::C-UUID,                             # Binary type = UUID
      $uuid.Blob.List,                          # Binary Data

    # 5
    BSON::C-BOOLEAN,                            # 0x08
      0x62, 0x66, 0x00,                         # 'bf'
      0x00,                                     # False

    # 5
    BSON::C-BOOLEAN,                            # 0x08
      0x62, 0x74, 0x00,                         # 'bt'
      0x01,                                     # True

    0x00                                        # End document
  );

#  say "Size handyman Buf: ", $etst.elems;

  # Encode document and compare with handcrafted byte array
  #
  my Buf $edoc = $d.encode;
  is-deeply $edoc, $etst, 'Encoded document is correct';

  # Fresh doc, load handcrafted data and decode into document
  #
  diag "Sequence of keys";

  $d .= new;
  $d.decode($etst);
  is $d<a>, 1234, "a => $d<a>, int32";
  is $d<b>, -203.345, "b => $d<b>, double";
  is $d<v>, 4295392664, "v => $d<v>, int64";

  is $d<w>.^name, 'BSON::Javascript', 'Javascript code on $d<w>';
  is $d<w>.javascript, 'function(x){return x;}', 'Code is same';

  is $d<abcdef><a1>, 10, "nest \$d<abcdef><a1> = $d<abcdef><a1>";
  is $d<abcdef><b1><q>, 255, "nest \$d<abcdef><b1><q> = $d<abcdef><b1><q>";

  is $d<jss>.^name, 'BSON::Javascript', 'Javascript code on $d<w>';
  is $d<jss>.javascript, 'function(x){return x;}', 'Code is same';
  is $d<jss>.scope<nn>, 10, "\$d<jss>.scope<nn> = {$d<jss>.scope<nn>}";

  is-deeply $d<bin>.binary-data.List, $uuid.Blob.List, "UUID binary data ok";
  is $d<bin>.binary-type, BSON::C-UUID, "Binary type is UUID";

  ok $d<bf> ~~ False, "Boolean False";
  ok $d<bt> ~~ False, "Boolean True";

  # Test sequence
  #
  diag "Sequence of index";

  is $d[0], -203.345.Num, "0: $d[0], double";
  is $d[1], 1234, "1: $d[1], int32";
  is $d[2], 4295392664, "2: $d[2], int64";
  is $d[3].^name, 'BSON::Javascript', '3:Javascript code on $d<w>';
  is $d[4][0], 10, "4: nest 10";
  is $d[4][1], 11, "4: nest 11";
  is $d[4][2][0], 255, "4: subnest 255";
  is $d[5].javascript, 'function(x){return x;}', "5: '{$d[5].javascript}'";
  is $d[6].binary-type, BSON::C-UUID, "6: Binary type is UUID";
  ok $d[7] ~~ False, "Boolean False";
  ok $d[8] ~~ False, "Boolean True";

}, "Document encoding decoding types";

#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Cleanup
#
done-testing();
exit(0);
