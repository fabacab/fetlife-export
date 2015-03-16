#!/bin/bash -
cat << "EOF"
@@@@@@@@  @@@@@@@@  @@@@@@@  @@@       @@@  @@@@@@@@  @@@@@@@@
@@@@@@@@  @@@@@@@@  @@@@@@@  @@@       @@@  @@@@@@@@  @@@@@@@@
@@!       @@!         @@!    @@!       @@!  @@!       @@!     
!@!       !@!         !@!    !@!       !@!  !@!       !@!     
@!!!:!    @!!!:!      @!!    @!!       !!@  @!!!:!    @!!!:!  
!!!!!:    !!!!!:      !!!    !!!       !!!  !!!!!:    !!!!!:  
!!:       !!:         !!:    !!:       !!:  !!:       !!:     
:!:       :!:         :!:     :!:      :!:  :!:       :!:     
 ::        :: ::::     ::     :: ::::   ::   ::        :: ::::
 :        : :: ::      :     : :: : :  :     :        : :: :: 
                                                              
                                                              
@@@@@@@@  @@@  @@@  @@@@@@@    @@@@@@   @@@@@@@   @@@@@@@     
@@@@@@@@  @@@  @@@  @@@@@@@@  @@@@@@@@  @@@@@@@@  @@@@@@@     
@@!       @@!  !@@  @@!  @@@  @@!  @@@  @@!  @@@    @@!       
!@!       !@!  @!!  !@!  @!@  !@!  @!@  !@!  @!@    !@!       
@!!!:!     !@@!@!   @!@@!@!   @!@  !@!  @!@!!@!     @!!       
!!!!!:      @!!!    !!@!!!    !@!  !!!  !!@!@!      !!!       
!!:        !: :!!   !!:       !!:  !!!  !!: :!!     !!:       
:!:       :!:  !:!  :!:       :!:  !:!  :!:  !:!    :!:       
 :: ::::   ::  :::   ::       ::::: ::  ::   :::     ::       
: :: ::    :   ::    :         : :  :    :   : :     :        
                                                              
                                                              
@@@  @@@  @@@  @@@  @@@@@@@@   @@@@@@   @@@@@@@   @@@@@@@     
@@@  @@@  @@@  @@@  @@@@@@@@  @@@@@@@@  @@@@@@@@  @@@@@@@@    
@@!  @@!  @@!  @@!       @@!  @@!  @@@  @@!  @@@  @@!  @@@    
!@!  !@!  !@!  !@!      !@!   !@!  @!@  !@!  @!@  !@!  @!@    
@!!  !!@  @!@  !!@     @!!    @!@!@!@!  @!@!!@!   @!@  !@!    
!@!  !!!  !@!  !!!    !!!     !!!@!!!!  !!@!@!    !@!  !!!    
!!:  !!:  !!:  !!:   !!:      !!:  !!!  !!: :!!   !!:  !!!    
:!:  :!:  :!:  :!:  :!:       :!:  !:!  :!:  !:!  :!:  !:!    
 :::: :: :::    ::   :: ::::  ::   :::  ::   :::   :::: ::    
  :: :  : :    :    : :: : :   :   : :   :   : :  :: :  :     
EOF
echo
echo "FETLIFE EXPORT WIZARD"
echo "This software is released to the public domain. Fuck copyright."
echo
echo "Make a copy of your own or any other user's FetLife account."
echo

readonly FL_EXPORT="fetlife-export.pl"
readonly DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

echo "You will need a FetLife account to use this tool. If you don't"
echo "have a FetLife account, you can easily create one at this page:"
echo "    https://FetLife.com/signup"
echo "Creating a FetLife account is free and does not require a valid"
echo "email address or other personally identifying information. For"
echo "maximum security, create an account while using the Tor Browser."
echo "    https://torproject.org/"
echo
echo -n "Type your FetLife username, then press return: "
read USERNAME
echo

echo "Type the name of a folder to save to, or leave blank to use the default shown."
echo "If this folder does not exist, it will be created."
echo -n "Save to folder [$DIR]: "
read SAVE_TO_FOLDER
echo

echo "Type the ID number of the export target. For example, if you want to"
echo "create a copy of JohnBaku's entire FetLife history, type: 1"
echo "Leave blank to automatically detect and use $USERNAME's ID number."
echo -n "Export target's user ID: "
read TARGET_USER_ID
echo

echo "Use a proxy? (Leave blank to make a direct connection.)"
echo "If you want to use a proxy, enter the proxy's URL here. For example,"
echo "to make use of a default Tor Browser, type: socks://localhost:9150"
echo -n "Proxy URL: "
read PROXYURL
echo

if [ ! -z "$PROXYURL" ]; then
    PROXYOPT="--proxy=$PROXYURL"
fi
if [ -z "$SAVE_TO_FOLDER" ]; then
    SAVE_TO_FOLDER="$DIR"
fi

echo "$FL_EXPORT will now run with these parameters:"
echo $FL_EXPORT $PROXYOPT $USERNAME $SAVE_TO_FOLDER $TARGET_USER_ID
echo
echo "When prompted next, enter the password for $USERNAME."
"$DIR"/$FL_EXPORT $PROXYOPT $USERNAME $SAVE_TO_FOLDER $TARGET_USER_ID
