#!/usr/bin/env python3

import re

from scapy.all import *

######################################

import numpy as np
import wave
import struct
# import winsound

def generate_chord(frequencies, duration=2.0, sample_rate=44100):
    """
    Generates a chord with the given frequencies.
    
    :param frequencies: List or array of frequencies for the chord.
    :param duration: Duration of the chord in seconds.
    :param sample_rate: Sample rate of the audio.
    :return: Numpy array containing the audio data.
    """
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    audio_data = np.zeros_like(t)
    for freq in frequencies:
        audio_data += np.sin(2 * np.pi * freq * t)
    audio_data /= np.max(np.abs(audio_data))  # Normalize to the range [-1, 1]
    return audio_data

def save_wav(filename, data, sample_rate=44100):
    """
    Saves the audio data to a WAV file.
    
    :param filename: Name of the file to save.
    :param data: Numpy array containing the audio data.
    :param sample_rate: Sample rate of the audio.
    """
    with wave.open(filename, 'w') as wf:
        wf.setnchannels(1)  # Mono audio
        wf.setsampwidth(2)  # 16-bit audio
        wf.setframerate(sample_rate)
        for sample in (data * 32767).astype(np.int16):
            wf.writeframes(struct.pack('<h', sample))

# def play_wav(filename):
#    """
#    Plays the WAV file using winsound.
#    
#    :param filename: Name of the file to play.
#    """
#    winsound.PlaySound(filename, winsound.SND_FILENAME)

######################################



class P4chord(Packet):
    name = "P4chord"
    fields_desc = [ StrFixedLenField("P", "P", length=1),
                    StrFixedLenField("Four", "4", length=1),
                    StrFixedLenField("P", "P", length=1),
                    StrFixedLenField("Four", "4", length=1),
                    StrFixedLenField("ChordType", "M_", length=2),
                    StrFixedLenField("tonic", "Af", length=2),
                    IntField("ChosenNotes", 4660),
                    IntField("freq1", 110),
                    IntField("freq2", 220),
                    IntField("freq3", 440),
                    IntField("freq4", 880)]
              

bind_layers(Ether, P4chord, type=0x1234)

class NumParseError(Exception):
    pass

class OpParseError(Exception):
    pass

class Token:
    def __init__(self,type,value = None):
        self.type = type
        self.value = value

def note_parser(s, i, ts):
    pattern = "^\s*(Af|An|As|Bf|Bn|Bs|Cf|Cn|Cs|Df|Dn|Ds|Ef|En|Es|Ff|Fn|Fs|Gf|Gn|Gs)\s*"
    match = re.match(pattern,s[i:])
    if match:
        ts.append(Token('num', match.group(1)))
        return i + match.end(), ts
    raise NumParseError('Expected a note!')


def chord_parser(s, i, ts):
    pattern = "^\s*(M_|M7|m_|m7|di|do|a6)\s*"
    match = re.match(pattern,s[i:])
    if match:
        ts.append(Token('num', match.group(1)))
        return i + match.end(), ts
    raise NumParseError("Expected chord operator 'M_', 'M7', 'm_', 'm7', 'di', 'do' or 'a6'.")
    
    
def chose_parser(s, i, ts):
    pattern = "^\s*([0-9A-Fa-f]+)\s*"
    match = re.match(pattern,s[i:])
    if match:
        hex_string = match.group(1)
        decimal_value = int(hex_string, 16)  # Convert hexadecimal string to integer
        ts.append(Token('num', decimal_value))
        return i + match.end(), ts
    raise NumParseError('Expected a note!')



def make_seq(p1, p2):
    def parse(s, i, ts):
        i,ts2 = p1(s,i,ts)
        return p2(s,i,ts2)
    return parse

def get_if():
    ifs=get_if_list()
    iface= "veth0-1" # "h1-eth0"
    #for i in get_if_list():
    #    if "eth0" in i:
    #        iface=i
    #        break;
    #if not iface:
    #    print("Cannot find eth0 interface")
    #    exit(1)
    #print(iface)
    return iface

def main():

    p = make_seq(note_parser, make_seq(chord_parser,chose_parser))
    s = ''
    #iface = get_if()
    iface = "enx0c37965f8a14"

    while True:
        s = input('> ')
        if s == "quit":
            break
        print(s)
        try:
            i,ts = p(s,0,[])
            pkt = Ether(dst='00:04:00:00:00:00', type=0x1234) / P4chord(ChordType=ts[1].value,
                                              tonic=ts[0].value,
                                              ChosenNotes=int(ts[2].value))

            pkt = pkt/' '

            #pkt.show()
            resp = srp1(pkt, iface=iface,timeout=5, verbose=False)
            if resp:
                p4chord=resp[P4chord]
                if p4chord:
                    print(p4chord.freq1)
                    print(p4chord.freq2)
                    print(p4chord.freq3)
                    print(p4chord.freq4)
                    
                    # Generate the chord
                    audio_data = generate_chord([p4chord.freq1,p4chord.freq2,p4chord.freq3,p4chord.freq4], duration, sample_rate)

                    # Sve to a WAV file
                    save_wav("chord.wav", audio_data, sample_rate)
                    # ...go and play this file!

                    # Play the WAV file
                 #   play_wav(wav_filename)


                else:
                    print("cannot find P4chord header in the packet")
            else:
                print("Didn't receive response")
        except Exception as error:
            print(error)


if __name__ == '__main__':
    main()


