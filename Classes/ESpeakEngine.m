//
//  SpeachEngine.m
//  eSpeak
//
//  Created by Ing. Jozef Bozek on 24.8.2010.
//	Copyright © 2010 bring-it-together s.r.o.. All Rights Reserved.
// 
//	Redistribution and use in source and binary forms, with or without 
//	modification, are permitted provided that the following conditions are met:
//
//	1. Redistributions of source code must retain the above copyright notice, this 
//	   list of conditions and the following disclaimer.
//
//	2. Redistributions in binary form must reproduce the above copyright notice, 
//	   this list of conditions and the following disclaimer in the documentation 
//	   and/or other materials provided with the distribution.
//
//	3. Neither the name of the author nor the names of its contributors may be used
//	   to endorse or promote products derived from this software without specific
//	   prior written permission.
//
//	THIS SOFTWARE IS PROVIDED BY BRING-IT-TOGETHER S.R.O. "AS IS"
//	AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//	IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//	DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
//	FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//	DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//	SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//	OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//	OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "ESpeakEngine.h"
#import "speak_lib.h"

/* Callback from espeak.  Should call back to the TTS API */
static int eSpeakCallback(short *wav, int numsamples,
						  espeak_EVENT *events) {    
    
    if (wav == NULL) {
        return 1;
    }
	
    // The user data should contain the file pointer of the file to write to
    void* user_data = events->user_data;
	NSMutableData * data = (NSMutableData*)(user_data);
	[data appendBytes:wav length:(numsamples*sizeof(short))];
    //FILE* fp = (FILE *)(user_data);
	
    // Write all of the samples
    //fwrite(wav, sizeof(short), numsamples, fp);
    return 0;  // continue synthesis (1 is to abort)
}

@interface ESpeakEngine () <AVAudioPlayerDelegate>


@end


@implementation ESpeakEngine

@synthesize volume;
@synthesize delegate;

+ (void)initialize {
	
}

-(id)init {
	if (self = [super init]) {
		NSString * path = [[NSBundle mainBundle] bundlePath];
		
		int sampleRate  = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 4096, [path UTF8String], 0);
		if (sampleRate <= 0) {
			NSLog(@"eSpeak initialization failed!");
			[self release];
			self = nil;
			return nil;
		}
		
		self.volume = 1.0;
		
		espeak_SetSynthCallback(eSpeakCallback);
		
		[self setSpeechRate:140];
		
		espeak_VOICE voice;
		memset( &voice, 0, sizeof(espeak_VOICE)); // Zero out the voice first
		const char *langNativeString = "en-us";   //Default to US English
		voice.languages = langNativeString;
		voice.gender = 1;
		voice.age = 20;
		espeak_ERROR err = espeak_SetVoiceByProperties(&voice);
		if (err != EE_OK) {
			NSLog(@"eSpeak initialization failed!");
			[self release];
			self = nil;
			return nil;
		}
		
		espeak_SetParameter(espeakCAPITALS, 0, 0);
		espeak_SetParameter(espeakWORDGAP, 3, 0);
	}
	
    return self;
}

- (void)setLanguage:(NSString*)language {
	espeak_VOICE voice = {0};
    voice.languages = [language UTF8String];
    voice.variant = 0;
	
    if (strlen(voice.languages) > 2){
		char espeakLangStr[6];
		sprintf(espeakLangStr, "en-us");
		voice.languages = espeakLangStr;
    }
	
    espeak_ERROR err = espeak_SetVoiceByProperties(&voice);
	if (err != EE_OK) {
		NSLog(@"Error=%d while setting language: %@", err, language);
	}
}

- (void)setSpeechRate:(NSInteger)speechRate {
	espeak_ERROR err = espeak_SetParameter(espeakRATE, speechRate, 0);
	if (err != EE_OK) {
		NSLog(@"Error=%d while setting speech rate: %d", err, speechRate);
	}
}

- (void)setPitch:(NSInteger)pitch {
	espeak_ERROR err = espeak_SetParameter(espeakPITCH, pitch, 0);
	if (err != EE_OK) {
		NSLog(@"Error=%d while setting speech pitch: %d", err, pitch);
	}
}

- (void)setRange:(NSInteger)range {
	espeak_ERROR err = espeak_SetParameter(espeakRANGE, range, 0);
	if (err != EE_OK) {
		NSLog(@"Error=%d while setting speech range: %d", err, range);
	}
}

- (void)setVolume1:(NSInteger)val {
	espeak_ERROR err = espeak_SetParameter(espeakVOLUME, val, 0);
	if (err != EE_OK) {
		NSLog(@"Error=%d while setting volume: %d", err, val);
	}
}

- (void)setGender:(ESpeakEngineGener)gender {
	espeak_VOICE voice = {0};
	voice.gender = gender;
	espeak_ERROR err = espeak_SetVoiceByProperties(&voice);
	if (err != EE_OK) {
		NSLog(@"Error=%d while setting gender: %d", err, gender);
	}
}

- (NSArray*)supportedLanguages {
	NSMutableArray * voices = [NSMutableArray arrayWithCapacity:10];
	
	const espeak_VOICE ** list = espeak_ListVoices(NULL);
	int idx = 0;
	while (list[idx] != NULL) {
		NSString * language = [NSString stringWithFormat:@"%s", list[idx++]->languages];
		[voices addObject:language];	
	}
	
	return voices;
}

- (BOOL)isPlaying {
	return [player isPlaying];
}

//synthDoneCB_t synthDoneCBPtr;

-(void)speak:(NSString *)text {
	if ([player isPlaying]) {
		[self stop];
	}
	
    espeak_SetSynthCallback(eSpeakCallback);
	
	NSMutableData * data = [[NSMutableData alloc] init];
    char header[44]= {0};
	[data appendBytes:header length:44];
	
    unsigned int unique_identifier;
    espeak_ERROR err = espeak_Synth([text UTF8String],
                       strlen([text UTF8String]),
                       0,  // position
                       POS_SENTENCE,
                       0,  // end position (0 means no end position)
                       espeakCHARS_UTF8,
                       &unique_identifier,
                       data);
	
    err = espeak_Synchronize();
	
	long filelen = data.length;
		
    int samples = (((int)filelen) - 44) / 2;
    header[0] = 'R';
    header[1] = 'I';
    header[2] = 'F';
    header[3] = 'F';
    ((uint32_t *)(&header[4]))[0] = filelen - 8;
    header[8] = 'W';
    header[9] = 'A';
    header[10] = 'V';
    header[11] = 'E';
	
    header[12] = 'f';
    header[13] = 'm';
    header[14] = 't';
    header[15] = ' ';
	
    ((uint32_t *)(&header[16]))[0] = 16;  // size of fmt
	
    ((uint32_t *)(&header[20]))[0] = 1;  // format
    ((uint32_t *)(&header[22]))[0] = 1;  // channels
    ((uint32_t *)(&header[24]))[0] = 22050;  // samplerate
    ((uint32_t *)(&header[28]))[0] = 44100;  // byterate
    ((uint32_t *)(&header[32]))[0] = 2;  // block align
    ((uint32_t *)(&header[34]))[0] = 16;  // bits per sample
	
    header[36] = 'd';
    header[37] = 'a';
    header[38] = 't';
    header[39] = 'a';
	
    ((uint32_t *)(&header[40]))[0] = samples * 2;  // size of data
	
	NSRange range = {0, 44};
	[data replaceBytesInRange:range withBytes:header];
	
	// Play the sound back.
	NSError *error = nil;
	[player release];
	player = [[AVAudioPlayer alloc] initWithData:data error:&error];
	[player setDelegate:self];
	player.volume = self.volume;
	if (error) {
		[self.delegate speechEngineErrorDidOccur:self error:error];
		return;
	}
	
	[player prepareToPlay];
	[self.delegate speechEngineDidStartSpeaking:self successfully:YES];
	[player play];
	[data release];
	
}

/* audioPlayerDidFinishPlaying:successfully: is called when a sound has finished playing. This method is NOT called if the player is stopped due to an interruption. */
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
	[self.delegate speechEngineDidFinishSpeaking:self successfully:flag];
}

/* if an error occurs while decoding it will be reported to the delegate. */
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
	[self.delegate speechEngineErrorDidOccur:self error:error];
}

/* audioPlayerBeginInterruption: is called when the audio session has been interrupted while the player was playing. The player will have been paused. */
- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player {
	[self.delegate speechEngineBeginInterruption:self];
}

/* audioPlayerEndInterruption: is called when the audio session interruption has ended and this player had been interrupted while playing. 
 The player can be restarted at this point. */
- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player {
	[self.delegate speechEngineEndInterruption:self];
}

- (void)stop {
	[player stop];
	[player release];
	player = nil;
	[self.delegate speechEngineDidFinishSpeaking:self successfully:NO];
}

- (void)dealloc {
	[player release];
	espeak_Terminate();
	[super dealloc];
}

@end
