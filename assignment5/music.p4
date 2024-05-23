/*
 * 
 *
 
 
 
This program sends back to the lab computer a set of frequencies associated with a chord definition, for playback on the lab computer.
 
 
 * This program implements a simple protocol. It can be carried over Ethernet
 * (Ethertype 0x1234).
 
 My custom Chord Protocol header p4chord (32 bits per line):
  
 *         0                1                2                3
 * +----------------+----------------+----------------+----------------+
 * |       P        |      four      |              tonic              |
 * +----------------+----------------+----------------+----------------+
 * |            ChordType            |     bfreq1     |     bfreq2     |
 * +----------------+----------------+----------------+----------------+
 * |     bfreq3     |                    ChosenNotes                   |
 * +----------------+----------------+----------------+----------------+
 * |       tfreq1       |       tfreq2       |        tfreq3      |....|
 * +----------------+----------------+----------------+----------------+

 

 
 P is an ASCII Letter 'P' (0x50)
 4 is an ASCII Letter '4' (0x34)
 tonic is two ASCII Letters:
 	1) A, B, C, D, E, F or G (keyboard notes)
 		(ASCII 0x41-0x47)
 	2) f,n,s (whether the note is flat, natural, or sharp)
 		(ASCII 0x66 0x6e 0x73 respectively)
 	e.g. represent As with 0x4173
 		
ChordType is two ASCII letters, one of the following:
 	M_ (4D 5F) for a major chord
 	M7 (4D 37) for a major 7th chord
 	m_ (6D 5F) for a minor chord
 	m7 (6D 37) for a minor 7th chord
 	di (64 69) for a diminished 7th chord
 	do (64 6F) for a dominant 7th chord
 	a6 (61 36) for an augmented 6th chord

By default, up to 16 frequencies will be defined in the raspberry pi that correspond with this chord, and each frequency is assigned a 4-bit index 1-16. Then, ChosenNotes contains 6 indexes which choose the notes to put into bfreq1/2/3 and tfreq1/2/3. This way, we can maintain complete control over the chord we produce when defining it at the client - it is in effect a more advanced way of controlling chord inversions.

The frequencies are outputs.
I will work mainly in the range A2 (110Hz) to A5 (880Hz).
bfreq1, bfreq2, and bfreq3 are bass frequencies in Hz with 8 bits assigned (up to 255Hz)
tfreq1, tfreq2, tfreq3 are treble frequencies - these are 10 bits long and will be assigned to
frequencies 256Hz or greater.
 
 *
 * The device receives a packet, performs the requested operation, fills in the
 * result and sends the packet back out of the same port it came in on, while
 * swapping the source and destination addresses.
 *
 * If an unknown operation is specified or the header is not valid, the packet
 * is dropped
 */

#include <core.p4>
#include <v1model.p4>

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<8>  bfreq_t
typedef bit<10> tfreq_t


/*
 * Define the headers the program will recognize
 */

/*
 * Standard Ethernet header
 */
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}


// Using etherType 0x1234: 
const bit<16> ETYPE = 0x1234;

// Letters to identify this header type
const bit<8>  P = 0x43;      // 'P'
const bit<8>  four = 0x34;   // '4'

// Possible tonic notes (21 defined - although there will be some overlap! see later)
const bit<16> Af = 0x4166;
const bit<16> An = 0x416e;
const bit<16> As = 0x4173;
const bit<16> Bf = 0x4266;
const bit<16> Bn = 0x426e;
const bit<16> Bs = 0x4273;
const bit<16> Cf = 0x4366;
const bit<16> Cn = 0x436e;
const bit<16> Cs = 0x4373;
const bit<16> Df = 0x4466;
const bit<16> Dn = 0x446e;
const bit<16> Ds = 0x4473;
const bit<16> Ef = 0x4566;
const bit<16> En = 0x456e;
const bit<16> Es = 0x4573;
const bit<16> Ff = 0x4666;
const bit<16> Fn = 0x466e;
const bit<16> Fs = 0x4673;
const bit<16> Gf = 0x4766;
const bit<16> Gn = 0x476e;
const bit<16> Gs = 0x4773;

// Possible note frequencies (over the range of 3 octaves
const bit<10> 


// Possible chord types (7 defined but we can add more if we like)
const bit<32> major = 0x4D5F
const bit<32> major7 = 0x4D37
const bit<32> minor = 0x6D5F
const bit<32> minor7 = 0x6D37
const bit<32> diminished7 = 0x6469
const bit<32> dominant7 = 0x646F
const bit<32> augmented6 = 0x6136


header p4chord_t {
    bit<8>  P;
    bit<8>  four;
    bit<16> tonic;
    bit<16> ChordType;
    bit<8>  bfreq1;
    bit<8>  bfreq2;
    bit<8>  bfreq3;
    bit<24> ChosenNotes
    bit<10> tfreq1;
    bit<10> tfreq2;
    bit<10> tfreq3;
    bit<2>  favnum
}

/*
 * All headers, used in the program needs to be assembled into a single struct.
 * We only need to declare the type, but there is no need to instantiate it,
 * because it is done "by the architecture", i.e. outside of P4 functions
 */
struct headers {
    ethernet_t   ethernet;
    p4chord_t     p4chord;
}

/*
 * All metadata, globally used in the program, also  needs to be assembled
 * into a single struct. As in the case of the headers, we only need to
 * declare the type, but there is no need to instantiate it,
 * because it is done "by the architecture", i.e. outside of P4 functions
 */

struct metadata {
    /* In our case it is empty */
}

/*************************************************************************
 ***********************  P A R S E R  ***********************************
 *************************************************************************/
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            ETYPE : check_p4chord;
            default       : accept;
        }
    }

    state check_p4chord {
        transition select(
        packet.lookahead<p4chord_t>().P,
        packet.lookahead<p4chord_t>().four) {
            (P, four) : parse_p4chord;
            default                          : accept;
        }
    }

    state parse_p4chord {
        packet.extract(hdr.p4chord);
        transition accept;
    }
}

/*************************************************************************
 ************   C H E C K S U M    V E R I F I C A T I O N   *************
 *************************************************************************/
control MyVerifyChecksum(inout headers hdr,
                         inout metadata meta) {
    apply { }
}

/*************************************************************************
 **************  I N G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
                  
    action send_back(bit<8> bfreq1, bit<8> bfreq2, bit<8> bfreq3, bit<10> tfreq1, bit<10> tfreq2, bit<10> tfreq3) {
        /* TODO
         * - put the frequencies into hdr.p4chord.bfreq1,bfreq2,bfreq3,tfreq1,tfreq2,tfreq3
         * - swap MAC addresses in hdr.ethernet.dstAddr and
         *   hdr.ethernet.srcAddr using a temp variable
         * - Send the packet back to the port it came from
             by saving standard_metadata.ingress_port into
             standard_metadata.egress_spec
         */
         
         hdr.p4chord.bfreq1 = bfreq1;
         hdr.p4chord.bfreq2 = bfreq2;
         hdr.p4chord.bfreq3 = bfreq3;
         hdr.p4chord.tfreq1 = tfreq1;
         hdr.p4chord.tfreq2 = tfreq2;
         hdr.p4chord.tfreq3 = tfreq3;
          
         macAddr_t temp;
         temp = hdr.ethernet.dstAddr;
         hdr.ethernet.dstAddr = hdr.ethernet.srcAddr;
         hdr.ethernet.srcAddr = temp;
         standard_metadata.egress_spec = standard_metadata.ingress_port;
    }

    action major() {
    	if(hdr.p4chord.tonic == Ab || hdr.p4chord.tonic == Gs){
    		f_root = 52 // frequency of lowest instance of this tonic
        	send_back(bfreq1,bfreq2,bfreq3,tfreq1,tfreq2,tfreq3);
        }
    }

    action major7() {

    }

    action minor() {

    }

    action minor7() {

    }






















    table calculate {
        key = {
            hdr.p4calc.op        : exact;
        }
        actions = {
            operation_add;
            operation_sub;
            operation_and;
            operation_or;
            operation_xor;
            operation_drop;
        }
        const default_action = operation_drop();
        const entries = {
            P4CALC_PLUS : operation_add();
            P4CALC_MINUS: operation_sub();
            P4CALC_AND  : operation_and();
            P4CALC_OR   : operation_or();
            P4CALC_CARET: operation_xor();
        }
    }

    apply {
        if (hdr.p4calc.isValid()) {
            calculate.apply();
        } else {
            operation_drop();
        }
    }
}

/*************************************************************************
 ****************  E G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

/*************************************************************************
 *************   C H E C K S U M    C O M P U T A T I O N   **************
 *************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

/*************************************************************************
 ***********************  D E P A R S E R  *******************************
 *************************************************************************/
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.p4calc);
    }
}

/*************************************************************************
 ***********************  S W I T T C H **********************************
 *************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
