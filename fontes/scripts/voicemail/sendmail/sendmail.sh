#! /bin/sh 
# Asterisk voicemail attachment conversion script, including voice recognition using Google API
#
# Revision history :
# 22/11/2010 - V1.0 - Creation by N. Bernaerts
# 07/02/2012 - V1.1 - Add handling of mails without attachment (thanks to Paul Thompson)
# 01/05/2012 - V1.2 - Use mktemp, pushd & popd
# 08/05/2012 - V1.3 - Change mp3 compression to CBR to solve some smartphone compatibility (thanks to Luca Mancino)
# 01/08/2012 - V1.4 - Add PATH definition to avoid any problem (thanks to Christopher Wolff)
# 31/01/2013 - V2.0 - Add Google Voice Recognition feature (thanks to Daniel Dainty idea and sponsoring :-)
# 04/02/2013 - V2.1 - Handle error in case of voicemail too long to be converted
# 13/08/2013 - V2.1a - Add VOICEMAIL WITH SPEECH RECOGNITION USING GOOGLE API by Nicolas Bernaerts 
# 19/07/2014 - V2.1b - Correçòes para uso com a API V2 do Google Speech Recognition

# set language for voice recognition (en-US, en-GB, fr-FR, ...)
LANGUAGE="en-US"
# A chave abaixo pode funcionar, pois a criei exatamente para testes, porém com o uso excessivo pode ser removida
KEY=""AIzaSyCXXE2QtAR-Egbb0JSCPmWKMWJlu5szx2Y

# set PATH
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# save the current directory 
pushd .
 
# create a temporary directory and cd to it 
TMPDIR=$(mktemp -d)
cd $TMPDIR 
 
# dump the stream to a temporary file 
cat >> stream.org 
 
# get the boundary 
BOUNDARY=`grep "boundary=" stream.org | cut -d'"' -f 2` 
 
# cut the file into parts 
# stream.part - header before the boundary 
# stream.part1 - header after the bounday 
# stream.part2 - body of the message 
# stream.part3 - attachment in base64 (WAV file) 
# stream.part4 - footer of the message 
awk '/'$BOUNDARY'/{i++}{print > "stream.part"i}' stream.org 
 
# if mail is having no audio attachment (plain text) 
PLAINTEXT=`cat stream.part1 | grep 'plain'` 
if [ "$PLAINTEXT" != "" ] 
then 
 
  # prepare to send the original stream 
  cat stream.org > stream.new 
 
# else, if mail is having audio attachment 
else 
 
  # cut the attachment into parts 
  # stream.part3.head - header of attachment 
  # stream.part3.wav.base64 - wav file of attachment (encoded base64) 
  sed '7,$d' stream.part3 > stream.part3.wav.head 
  sed '1,6d' stream.part3 > stream.part3.wav.base64 
 
  # convert the base64 file to a wav file 
  dos2unix -o stream.part3.wav.base64 
  base64 -di stream.part3.wav.base64 > stream.part3.wav 
 
  # convert wav file to mp3 file
  # -b 24 is using CBR, giving better compatibility on smartphones (you can use -b 32 to increase quality)
  # -V 2 is using VBR, a good compromise between quality and size for voice audio files
  lame -m m -b 24 stream.part3.wav stream.part3.mp3
 
  # convert back mp3 to base64 file 
  base64 stream.part3.mp3 > stream.part3.mp3.base64 
 
  # generate the new mp3 attachment header 
  # change Type: audio/x-wav to Type: audio/mpeg 
  # change name="msg----.wav" to name="msg----.mp3" 
  sed 's/x-wav/mpeg/g' stream.part3.wav.head | sed 's/.wav/.mp3/g' > stream.part3.mp3.head 
 
  # convert wav file to flac compatible for Google speech recognition
  sox stream.part3.wav -r 16000 -b 16 -c 1 audio.flac vad reverse vad reverse lowpass -2 2500

  # call Google Voice Recognition sending flac file as POST
  curl --data-binary @audio.flac --header 'Content-type: audio/x-flac; rate=16000' 'https://www.google.com/speech-api/v1/recognize?xjerr=1&client=chromium&pfilter=0&lang='$LANGUAGE'&maxresults=1&key='$KEY'' 1>audio.txt

  # extract the transcript and confidence results
  FILETOOBIG=`cat audio.txt | grep "<HTML>"`
  TRANSCRIPT=`cat audio.txt | cut -d"," -f3 | sed 's/^.*utterance\":\"\(.*\)\"$/\1/g'`
  CONFIDENCE=`cat audio.txt | cut -d"," -f4 | sed 's/^.*confidence\":0.\([0-9][0-9]\).*$/\1/g'`

  # generate first part of mail body, converting it to LF only
  mv stream.part stream.new
  cat stream.part1 >> stream.new
  sed '$d' < stream.part2 >> stream.new

  # beginning of transcription section
  echo "---" >> stream.new

  # if audio attachment is too big
  if [ "$FILETOOBIG" != "" ]
  then
    # error message
    echo "Voice message is too long to be transcripted." >> stream.new
  else
    # append result of transcription
    echo "Message seems to be ( $CONFIDENCE% confidence ) :" >> stream.new
    echo "$TRANSCRIPT" >> stream.new
  fi

  # end of message body
  tail -1 stream.part2 >> stream.new

  # append mp3 header
  cat stream.part3.mp3.head >> stream.new
  dos2unix -o stream.new

  # append base64 mp3 to mail body, keeping CRLF 
  unix2dos -o stream.part3.mp3.base64 
  cat stream.part3.mp3.base64 >> stream.new 
 
  # append end of mail body, converting it to LF only 
  echo "" >> stream.tmp 
  echo "" >> stream.tmp 
  cat stream.part4 >> stream.tmp 
  dos2unix -o stream.tmp 
  cat stream.tmp >> stream.new 
 
fi 
 
# send the mail thru sendmail 
cat stream.new | sendmail -t 
 
# go back to original directory 
popd
 
# remove all temporary files and temporary directory 
rm -Rf $TMPDIR

