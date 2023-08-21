# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Kernel/Modules/AgentITSMConfigItemLabelPrint.pm - print layout for itsm config item agent interface
# Copyright (C) 2019-2022 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::Modules::AgentITSMConfigItemLabelPrint;

use Imager::QRCode;
use strict;
use warnings;
use Kernel::Language qw(Translatable);
use constant mm => 25.4 / 72;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get params
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigItemID = $ParamObject->GetParam( Param => 'ConfigItemID' );
    my $VersionID    = $ParamObject->GetParam( Param => 'VersionID' );

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check needed stuff
    if ( !$ConfigItemID || !$VersionID ) {
        return $LayoutObject->ErrorScreen(
            Message => 'No ConfigItemID or VersionID is given!',
            Comment => 'Please contact the admin.',
        );
    }

    # get needed objects
    my $ConfigItemObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');
    my $ConfigObject     = $Kernel::OM->Get('Kernel::Config');

    $Self->{ConfigItemObject} = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');
    $Self->{PDFObject}        = $Kernel::OM->Get('Kernel::System::PDF');
    $Self->{HTMLUtilsObject}  = $Kernel::OM->Get('Kernel::System::HTMLUtils');
    $Self->{MainObject}  = $Kernel::OM->Get('Kernel::System::Main');
    $Self->{TimeObject} = $Kernel::OM->Get('Kernel::System::Time');

    # get config of frontend module
    $Self->{Config} = $ConfigObject->Get("ITSMConfigItem::Frontend::$Self->{Action}");

    # check for access rights
    my $HasAccess = $Self->{ConfigItemObject}->Permission(
        Scope  => 'Item',
        ItemID => $ConfigItemID,
        UserID => $Self->{UserID},
        Type   => $Self->{Config}->{Permission},
    );

    if ( !$HasAccess ) {

        # error page
        return $Self->{LayoutObject}->ErrorScreen(
            Message => 'Can\'t show config item, no access rights given!',
            Comment => 'Please contact the admin.',
        );
    }

    # get config item
    my $ConfigItem = $Self->{ConfigItemObject}->ConfigItemGet(
        ConfigItemID => $ConfigItemID,
    );
	
    if ( !$ConfigItem->{ConfigItemID} ) {
        return $Self->{LayoutObject}->ErrorScreen(
            Message => "ConfigItemID $ConfigItemID not found in database!",
            Comment => 'Please contact the admin.',
        );
    }

    # get version
    my $Version = $Self->{ConfigItemObject}->ConfigItemGet(
        VersionID => $VersionID,
    );
    if ( !$Version->{VersionID} ) {
        return $Self->{LayoutObject}->ErrorScreen(
            Message => "VersionID $VersionID not found in database!",
            Comment => 'Please contact the admin.',
        );
    }

    # get last version
    my $LastVersion = $Self->{ConfigItemObject}->ConfigItemGet(
        ConfigItemID => $ConfigItemID,
    );

    # generate pdf output
    if ( $Self->{PDFObject} ) {

        my %Page;
        my %Image;

        $Page{Width}           = $Self->{Config}->{PageSetting}->{PageWidth} / mm;     # (optional) default 595 (Din A4) - _ both or nothing
        $Page{Height}          = $Self->{Config}->{PageSetting}->{PageHeight} / mm;     # (optional) default 842 (Din A4) -
        $Page{PageOrientation} = $Self->{Config}->{PageSetting}->{PageOrientation};    # (optional) default normal (normal|landscape)
        $Page{MarginTop}       = $Self->{Config}->{PageSetting}->{MarginTop};           # (optional) default 0 -
        $Page{MarginRight}     = $Self->{Config}->{PageSetting}->{MarginRight};           # (optional) default 0  |_ all or nothing
        $Page{MarginBottom}    = $Self->{Config}->{PageSetting}->{MarginBottom};           # (optional) default 0  |
        $Page{MarginLeft}      = $Self->{Config}->{PageSetting}->{MarginLeft};           # (optional) default 0 -
        $Page{ShowPageNumber}  = 0;            # (optional) default 1

        # create new pdf document
        $Self->{PDFObject}->DocumentNew(
            Encode => $Self->{LayoutObject}->{UserCharset},
        );
		

        # create first pdf page
        $Self->{PDFObject}->PageBlankNew(
            %Page,
        );
     
        # output general information
        $Self->_PDFOutputGeneralInfos(
            Page       => \%Page,
            ConfigItem => $LastVersion,
        );

        # create file name
        my $Filename = $Self->{MainObject}->FilenameCleanUp(
            Filename => $ConfigItem->{Number},
            Type     => 'Attachment',
        );
        my ( $s, $m, $h, $D, $M, $Y ) = $Self->{TimeObject}->SystemTime2Date(
            SystemTime => $Self->{TimeObject}->SystemTime(),
        );
        $M = sprintf( "%02d", $M );
        $D = sprintf( "%02d", $D );
        $h = sprintf( "%02d", $h );
        $m = sprintf( "%02d", $m );

        return $Self->{LayoutObject}->Attachment(
            Filename    => 'configitem_' . $Filename . "_$Y-$M-$D\_$h-$m.pdf",
            ContentType => 'application/pdf',
            Content     => $Self->{PDFObject}->DocumentOutput(),
            Type        => 'attachment',
        );
    }

    # generate html output
    else {
        # TODO Error when no PDF is active.
        return;
    }
    
    return 1;
}

sub _PDFOutputGeneralInfos {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Page ConfigItem)) {
        if ( !defined $Param{$Argument} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    $Self->{LayoutObject} = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $TrueP = $Self->{PDFObject}->PositionSet(
        X    => $Self->{Config}->{LogoSetting}->{ImagePosition_X},         # (optional) (<integer>|left|center|right)
        Y    => $Self->{Config}->{LogoSetting}->{ImagePosition_Y},         # (optional) (<integer>|top|middle|bottom)
    );

    my %Image;
    $Image{File}   = $Self->{Config}->{LogoSetting}->{LogoPath};  # (gif|jpg|png)
    $Image{Type}   = $Self->{Config}->{LogoSetting}->{DisplayType};       # (optional) default Reduce (ReturnFalse|Reduce)
    $Image{Width}  = $Self->{Config}->{LogoSetting}->{ImageWidth};                # width of image
    $Image{Height} = $Self->{Config}->{LogoSetting}->{ImageHeight};                # height of image

    $Self->{PDFObject}->Image( %Image );

    my $TrueI = $Self->{PDFObject}->PositionSet(
        X    => $Self->{Config}->{TableSetting}->{TablePosition_X},         # (optional) (<integer>|left|center|right)
        Y    => $Self->{Config}->{TableSetting}->{TablePosition_Y},         # (optional) (<integer>|top|middle|bottom)
    );


    # Get CI Value 1..4
    my $TableRight = [];
    my $Barcode;
    my $Footer;
	
    for my $ConfigValue ( 1..5 ) {

        my $TableRow = {};
        my $CIKey = $Self->{Config}->{'Value'.$ConfigValue};

        if ($CIKey) {
            if ($Param{ConfigItem}->{$CIKey}) {

                $TableRow->{Key} = $CIKey;
                $TableRow->{Value} = $Param{ConfigItem}->{$CIKey};
                push (@{$TableRight}, $TableRow);
            } 
            elsif ($Param{ConfigItem}->{XMLData}->[1]->{'Version'}->[1]->{$CIKey}->[1]->{'Content'}) {

                $TableRow->{Key} = $CIKey;
                $TableRow->{Value} = $Param{ConfigItem}->{XMLData}->[1]->{'Version'}->[1]->{$CIKey}->[1]->{'Content'};
                push (@{$TableRight}, $TableRow);
            } 
        }
    } 

    # Get Barcode if Active = 1
	if ($Self->{Config}->{BarcodeSetting}->{Active} == 1) {
		if ( $Param{ConfigItem}->{ $Self->{Config}->{BarcodeSetting}->{BarcodeField} } ) {
			$Barcode = $Param{ConfigItem}->{ $Self->{Config}->{BarcodeSetting}->{BarcodeField} };
		} 
		elsif ($Param{ConfigItem}->{XMLData}->[1]->{'Version'}->[1]->{ $Self->{Config}->{BarcodeSetting}->{BarcodeField} }->[1]->{'Content'}) {
			$Barcode = $Param{ConfigItem}->{XMLData}->[1]->{'Version'}->[1]->{ $Self->{Config}->{BarcodeSetting}->{BarcodeField} }->[1]->{'Content'};
		}
	}
    # Get Footer
    $Footer = $Self->{Config}->{Footer};

    my $Rows = @{$TableRight};

    my %TableParam;
#    for my $Row ( 1 .. $Rows ) {
#        $Row--;
#        $TableParam{CellData}[0][0]{Content}         = $Self->{LayoutObject}->{LanguageObject}->Translate( $TableRight->[$Row]->{Key} ) . ':';
        $TableParam{CellData}[0][0]{Font}            = 'ProportionalBold';
        $TableParam{CellData}[0][0]{FontSize}            = 11;
        $TableParam{CellData}[0][0]{Align}            = 'center';
        $TableParam{CellData}[0][0]{Content}         = $Self->{LayoutObject}->{LanguageObject}->Translate( $TableRight->[0]->{Value} );

        $TableParam{CellData}[1][0]{Font}            = 'Proportional';
        $TableParam{CellData}[1][0]{FontSize}            = 8;
        $TableParam{CellData}[1][0]{Align}            = 'center';
        $TableParam{CellData}[1][0]{Content}         = 'servicedesk.phsg.ch';

        $TableParam{CellData}[2][0]{Font}            = 'Proportional';
        $TableParam{CellData}[2][0]{FontSize}            = 8;
        $TableParam{CellData}[2][0]{Align}            = 'center';
        $TableParam{CellData}[2][0]{Content}         = '+41 71 844 18 55';

        # Set Firstline bold
#        if ( $Row == 0 ) {
#        $TableParam{CellData}[$Row][0]{Font}            = $Self->{Config}->{TableSetting}->{Font};             
#        }
#    }

 #   $TableParam{ColumnData}[0]{Width} = $Self->{Config}->{TableSetting}->{TitleWidth};
    $TableParam{ColumnData}[0]{Width} = $Self->{Config}->{TableSetting}->{ValueWidth};
    $TableParam{Type}                 = $Self->{Config}->{TableSetting}->{Type};
    $TableParam{Border}               = $Self->{Config}->{TableSetting}->{Border};
    $TableParam{FontSize}             = $Self->{Config}->{TableSetting}->{FontSize};
    $TableParam{Padding}              = $Self->{Config}->{TableSetting}->{Padding};
    $TableParam{PaddingTop}           = $Self->{Config}->{TableSetting}->{PaddingTop};
    $TableParam{PaddingBottom}        = $Self->{Config}->{TableSetting}->{PaddingBottom};
    $TableParam{PaddingLeft}          = $Self->{Config}->{TableSetting}->{PaddingLeft}; 
    $TableParam{PaddingRight}          = $Self->{Config}->{TableSetting}->{PaddingRight};
#    $TableParam{Width} = 50;

    # output table (or a fragment of it)
    %TableParam = $Self->{PDFObject}->Table(%TableParam);

    my $TrueH = $Self->{PDFObject}->PositionSet(
        X    => $Self->{Config}->{HLineSetting}->{HLinePosition_X},         # (optional) (<integer>|left|center|right)
        Y    => $Self->{Config}->{HLineSetting}->{HLinePosition_Y},         # (optional) (<integer>|top|middle|bottom)
    );

#    my $TrueHLine = $Self->{PDFObject}->HLine(
#        Color     => $Self->{Config}->{HLineSetting}->{Color},     # (optional) default black
#        LineWidth => $Self->{Config}->{HLineSetting}->{LineWidth},             # (optional) default 1
#    );
	
	# Set window preferences
#	$Self->{PDFObject}->BarcodeWindowSetting ();
    my $TrueBarcode = $Self->{PDFObject}->PositionSet(
          X    => "left",         # (optional) (<integer>|left|center|right)
          Y    => "top",
    );
	
    # Get Barcode if Active = 1
	if ($Self->{Config}->{BarcodeSetting}->{Active} == 1) {
		my $BarcodeReturn = $Self->{PDFObject}->BarcodeGet(
			Barcode => $Barcode,
			Code    => $Self->{Config}->{BarcodeSetting}->{Code},
			Zone    => $Self->{Config}->{BarcodeSetting}->{Zone},         # (Optional) Default 10. Size of bars
			UMZN    => $Self->{Config}->{BarcodeSetting}->{UpperMendingZone},         # (Optional) Default 25. Upper "mending zone"
			LMZN    => $Self->{Config}->{BarcodeSetting}->{LowerMendingZone},         # (Optional) Default 15. Lower "mending zone"
			Font    => $Self->{Config}->{BarcodeSetting}->{Font},         # (Optional) Default 'Helvetica.
			FNSZ    => $Self->{Config}->{BarcodeSetting}->{FontSize},          # (Optional) Default 8. Font size
			X       => $Self->{Config}->{BarcodeSetting}->{BarcodePosition_X},         # (Optional) Default 10. Places an XObject on the page in the specified location.
			Y       => $Self->{Config}->{BarcodeSetting}->{BarcodePosition_Y},         # (Optional) Default 20. Places an XObject on the page in the specified location.
			Scale   => $Self->{Config}->{BarcodeSetting}->{Scale},         # (Optional) Default .5 . Size (scaling)
		);
	}

	my $TrueText = $Self->{PDFObject}->PositionSet(
            X    => $Self->{Config}->{FooterSetting}->{FooterPosition_X},         # (optional) (<integer>|left|center|right)
            Y    => $Self->{Config}->{FooterSetting}->{FooterPosition_Y},         # (optional) (<integer>|top|middle|bottom)
        );

#    my %Return = $Self->{PDFObject}->Text(
#        Text     =>  $Self->{LayoutObject}->{LanguageObject}->Get( $Self->{Config}->{FooterSetting}->{FooterText} ),              # Text
#        Font     => $Self->{Config}->{FooterSetting}->{Font},  # (optional) default Proportional  (see DocumentNew())
#        FontSize => $Self->{Config}->{FooterSetting}->{FontSize},                  # (optional) default 10
#        Color    => $Self->{Config}->{FooterSetting}->{Color},           # (optional) default #000000
#        Align    => $Self->{Config}->{FooterSetting}->{Align},            # (optional) default left (left|center|right)
#        Lead     => $Self->{Config}->{FooterSetting}->{Lead},                  # (optional) default 1 distance between lines
#    );

    return 1;
}

1;
