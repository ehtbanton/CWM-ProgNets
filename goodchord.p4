/*
 * 
 *
 
 
 
This program sends back to the lab computer a set of frequencies associated with a chord definition, for playback on the lab computer.

While not fully complete, it may be tested by running this code on the Raspberry Pi and the associated python file on the lab device.
Typing in e.g. "Af M_ 0x1567" will cause a sound file containing an A flat major chord called "chord.wav" to be created in the local folder.
Changing Af to Ds, Ef, Cs or Df will change the tonic note in the chord, changing M_ to m_ makes the chord minor, and changing 0x1567 to 0x1234 or 0x2468 changes the distribution of notes in the chord.
 
 * This program implements a simple protocol. It can be carried over Ethernet
 * (Ethertype 0x1234).
 
 My custom Chord Protocol header p4chord (32 bits per line):
  
 *         0                1                2                3
 * +----------------+----------------+----------------+----------------+
 * |       P        |      four      |       P2       |      four2     |
 * +----------------+----------------+----------------+----------------+
 * |            ChordType            |              tonic              |
 * +----------------+----------------+----------------+----------------+
 * |                             ChosenNotes                           |
 * +----------------+----------------+----------------+----------------+
 * |                               freq1                               |
 * +----------------+----------------+----------------+----------------+
 * |                               freq2                               |
 * +----------------+----------------+----------------+----------------+
 * |                               freq3                               |
 * +----------------+----------------+----------------+----------------+
 * |                               freq4                               |
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

By default, up to 16 frequencies will be defined in the raspberry pi that correspond with this chord, and each frequency is assigned a 4-bit index 1-16. Then, ChosenNotes contains 4 indexes which choose the notes to put into freq1/2/3/4. This way, we can maintain complete control over the chord we produce when defining it at the client - it is in effect a more advanced way of controlling chord inversions.

The frequencies are outputs.
I will work mainly in the range A2 (110Hz) to A5 (880Hz).
freq1, freq2, freq3, and freq4 are 16 bits long - I originally experimented with having 8-bit bass notes and 10-bit treble notes, but a standardised approach was easier.
 

The device receives a packet, performs the requested operation, fills in the
result and sends the packet back out of the same port it came in on, while
swapping the source and destination addresses.


 */

#include <core.p4>
#include <v1model.p4>

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;


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
const bit<8>  P2 = 0x43;      // 'P'
const bit<8>  four2 = 0x34;   // '4'

// Possible hex of tonic notes (21 defined - although there will be some overlap! see note frequencies)
const bit<16> hAf = 0x4166;
const bit<16> hAn = 0x416e;
const bit<16> hAs = 0x4173;
const bit<16> hBf = 0x4266;
const bit<16> hBn = 0x426e;
const bit<16> hBs = 0x4273;
const bit<16> hCf = 0x4366;
const bit<16> hCn = 0x436e;
const bit<16> hCs = 0x4373;
const bit<16> hDf = 0x4466;
const bit<16> hDn = 0x446e;
const bit<16> hDs = 0x4473;
const bit<16> hEf = 0x4566;
const bit<16> hEn = 0x456e;
const bit<16> hEs = 0x4573;
const bit<16> hFf = 0x4666;
const bit<16> hFn = 0x466e;
const bit<16> hFs = 0x4673;
const bit<16> hGf = 0x4766;
const bit<16> hGn = 0x476e;
const bit<16> hGs = 0x4773;


// Possible note frequencies (in a single octave, we may reach higher octaves by doubling)
const bit<32> fA = 110; // A2
const bit<32> fBf = 117;
const bit<32> fB = 123;
const bit<32> fC = 131; // C3
const bit<32> fCs = 139;
const bit<32> fD = 147;
const bit<32> fEf = 156;
const bit<32> fE = 165;
const bit<32> fF = 175;
const bit<32> fFs = 185;
const bit<32> fG = 196;
const bit<32> fGs = 208; // G#3 or Ab3



// Possible chord types (7 defined but we can add more if we like)
const bit<16> hM_ = 0x4D5F;  // M_
const bit<16> hM7 = 0x4D37; // M7
const bit<16> hm_ = 0x6D5F;  // m_
const bit<16> hm7 = 0x6D37; // m7
const bit<16> hdi = 0x6469; // di
const bit<16> hdo = 0x646F; // do
const bit<16> ha6 = 0x6136; // a6


header p4chord_t {
    bit<8>  P;
    bit<8>  four;
    bit<8>  P2;
    bit<8>  four2;
    bit<16> ChordType;
    bit<16> tonic;
    bit<32> ChosenNotes;
    bit<32> freq1;
    bit<32> freq2;
    bit<32> freq3;
    bit<32> freq4;
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
    // bit<16> fArr[36];
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
            ETYPE : parse_p4chord;
            default       : accept;
        }
    }

    /*state check_p4chord {
        transition select(
        packet.lookahead<p4chord_t>().P,
        packet.lookahead<p4chord_t>().four) {
            (P, four) : parse_p4chord;
            default                          : accept;
        }
    }*/

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
                  
 /*   action set_array_values() {
    	meta.fArr[0] = fA2;
    	meta.fArr[1] = fBb2;
  	meta.fArr[2] = fB2;
    	meta.fArr[3] = fC3;
     	meta.fArr[4] = fCs3;
    	meta.fArr[5] = fD3;
  	meta.fArr[6] = fEb3;
    	meta.fArr[7] = fE3;
    	meta.fArr[8] = fF3;
    	meta.fArr[9] = fFs3;
  	meta.fArr[10] = fG3;
    	meta.fArr[11] = fGs3;
     	meta.fArr[12] = fA2*2;
    	meta.fArr[13] = fBb2*2;
  	meta.fArr[14] = fB2*2;
    	meta.fArr[15 = fC3*2;
     	meta.fArr[16] = fCs3*2;
    	meta.fArr[17] = fD3*2;
  	meta.fArr[18] = fEb3*2;
    	meta.fArr[19] = fE3*2;
    	meta.fArr[20] = fF3*2;
    	meta.fArr[21] = fFs3*2;
  	meta.fArr[22] = fG3*2;
    	meta.fArr[23] = fGs3*2;
    	meta.fArr[24] = fA2*4;
    	meta.fArr[25] = fBb2*4;
  	meta.fArr[26] = fB2*4;
    	meta.fArr[27] = fC3*4;
     	meta.fArr[28] = fCs3*4;
    	meta.fArr[29] = fD3*4;
  	meta.fArr[30] = fEb3*4;
    	meta.fArr[31] = fE3*4;
    	meta.fArr[32] = fF3*4;
    	meta.fArr[33] = fFs3*4;
  	meta.fArr[34] = fG3*4;
    	meta.fArr[35] = fGs3*4;
    	*/	  		  	
                  
    action send_back(bit<32> f1, bit<32> f2, bit<32> f3, bit<32> f4, bit<32> f5, bit<32> f6, bit<32> f7, bit<32> f8, bit<32> f9) {
        /* TODO
         * - put the frequencies into hdr.p4chord.bfreq1,bfreq2,bfreq3,tfreq1,tfreq2,tfreq3
         * - swap MAC addresses in hdr.ethernet.dstAddr and
         *   hdr.ethernet.srcAddr using a temp variable
         * - Send the packet back to the port it came from
             by saving standard_metadata.ingress_port into
             standard_metadata.egress_spec
         */
         
	if(hdr.p4chord.ChosenNotes == 5479) { //hex 0x1567
        	freq1=f1;
		freq2=f5;
		freq3=f6;
		freq4=f7;
        }
        if(hdr.p4chord.ChosenNotes == 4660) { //hex 0x1234
        	freq1=f1;
		freq2=f2;
		freq3=f3;
		freq4=f4;
        }
	if(hdr.p4chord.ChosenNotes == 9320) { //hex 0x2468
        	freq1=f2;
		freq2=f4;
		freq3=f6;
		freq4=f8;
        }


         hdr.p4chord.freq1 = freq1;
         hdr.p4chord.freq2 = freq2;
         hdr.p4chord.freq3 = freq3;
         hdr.p4chord.freq4 = freq4;
          
         macAddr_t temp;
         temp = hdr.ethernet.dstAddr;
         hdr.ethernet.dstAddr = hdr.ethernet.srcAddr;
         hdr.ethernet.srcAddr = temp;
         standard_metadata.egress_spec = standard_metadata.ingress_port;
    }

    action major() {
    	if(hdr.p4chord.tonic == hAf || hdr.p4chord.tonic == hGs){
    		bit<32> f1 = fGs; // frequency of lowest instance of this tonic
    		bit<32> f2 = fC;
    		bit<32> f3 = fEf;
    		bit<32> f4 = fGs*2;
    		bit<32> f5 = fC*2;
    		bit<32> f6 = fEf*2;
    		bit<32> f7 = fGs*4;
    		bit<32> f8 = fC*4;
    		bit<32> f9 = fEf*4;	
        }
    	if(hdr.p4chord.tonic == hDf || hdr.p4chord.tonic == hCs){
    		bit<32> f1 = fCs; // frequency of lowest instance of this tonic
    		bit<32> f2 = fF;
    		bit<32> f3 = fGs;
    		bit<32> f4 = fCs*2;
    		bit<32> f5 = fF*2;
    		bit<32> f6 = fGs*2;
    		bit<32> f7 = fCs*4;
    		bit<32> f8 = fF*4;
    		bit<32> f9 = fGs*4;	
        }
    	if(hdr.p4chord.tonic == hEf || hdr.p4chord.tonic == hDs){
    		bit<32> f1 = fEf; // frequency of lowest instance of this tonic
    		bit<32> f2 = fG;
    		bit<32> f3 = fBf;
    		bit<32> f4 = fEf*2;
    		bit<32> f5 = fG*2;
    		bit<32> f6 = fBf*2;
    		bit<32> f7 = fEf*4;
    		bit<32> f8 = fG*4;
    		bit<32> f9 = fBf*4;	
        }
	send_back(f1,f2,f3,f4,f5,f6,f7,f8,f9);
    }

    action major7() {
  
    }

    action minor() {
    	if(hdr.p4chord.tonic == hAf || hdr.p4chord.tonic == hGs){
    		bit<32> f1 = fGs; // frequency of lowest instance of this tonic
    		bit<32> f2 = fB;
    		bit<32> f3 = fEf;
    		bit<32> f4 = fGs*2;
    		bit<32> f5 = fB*2;
    		bit<32> f6 = fEf*2;
    		bit<32> f7 = fGs*4;
    		bit<32> f8 = fB*4;
    		bit<32> f9 = fEf*4;	
        }
    	if(hdr.p4chord.tonic == hDf || hdr.p4chord.tonic == hCs){
    		bit<32> f1 = fCs; // frequency of lowest instance of this tonic
    		bit<32> f2 = fE;
    		bit<32> f3 = fGs;
    		bit<32> f4 = fCs*2;
    		bit<32> f5 = fE*2;
    		bit<32> f6 = fGs*2;
    		bit<32> f7 = fCs*4;
    		bit<32> f8 = fE*4;
    		bit<32> f9 = fGs*4;	
        }
    	if(hdr.p4chord.tonic == hEf || hdr.p4chord.tonic == hDs){
    		bit<32> f1 = fEf; // frequency of lowest instance of this tonic
    		bit<32> f2 = fFs;
    		bit<32> f3 = fBf;
    		bit<32> f4 = fEf*2;
    		bit<32> f5 = fFs*2;
    		bit<32> f6 = fBf*2;
    		bit<32> f7 = fEf*4;
    		bit<32> f8 = fFs*4;
    		bit<32> f9 = fBf*4;	
        }
	send_back(f1,f2,f3,f4,f5,f6,f7,f8,f9);
    }

    action minor7() {

    }
    
    action diminished7() {

    }
 
    action dominant7() {

    }
    
    action augmented6() {

    }
    

    action operation_drop() {
        mark_to_drop(standard_metadata);
    }



    table chordmake {
        key = {
            hdr.p4chord.ChordType : exact;
        }
        actions = {
            major;
            major7;
            minor;
            minor7;
            diminished7;
            dominant7;
            augmented6;            
            operation_drop;
        }
        const default_action = operation_drop();
        const entries = {
            hM_     : major();
            hM7     : major7();
            hm_     : minor();
            hm7     : minor7();
            hdi     : diminished7();
            hdo     : dominant7();
            ha6     : augmented6();
            
        }
    }

    apply {
    //    if (hdr.p4chord.isValid()) {
            chordmake.apply();
    //    } else {
     //       operation_drop();
     //   }
       // standard_metadata.egress_spec = standard_metadata.ingress_port;
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
        packet.emit(hdr.p4chord);
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
