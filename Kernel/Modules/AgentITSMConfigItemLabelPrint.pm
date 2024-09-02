# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Kernel/Modules/AgentITSMConfigItemLabelPrint.pm - print layout for itsm config item agent interface
# Copyright (C) 2019-2024 Rother OSS GmbH, https://otobo.io/
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

use strict;
use warnings;

# core modules

# CPAN modules

# OTOBO modules
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # set default values for mm
    $Self->{mm} = 25.4 / 72;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get needed objects
    my $ConfigItemObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');
    my $ConfigObject     = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject     = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject      = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $PDFObject        = $Kernel::OM->Get('Kernel::System::PDF');

    # get params
    my $ConfigItemID = $ParamObject->GetParam( Param => 'ConfigItemID' );
    my $VersionID    = $ParamObject->GetParam( Param => 'VersionID' );

    # check needed stuff
    if ( !$ConfigItemID || !$VersionID ) {
        return $LayoutObject->ErrorScreen(
            Message => 'No ConfigItemID or VersionID is given!',
            Comment => 'Please contact the admin.',
        );
    }

    # get config of frontend module
    $Self->{Config} = $ConfigObject->Get("ITSMConfigItem::Frontend::$Self->{Action}");

    # get config item by version id
    my $ConfigItem = $ConfigItemObject->ConfigItemGet(
        VersionID     => $VersionID,
        DynamicFields => 1,
    );

    # check if config item exists
    if ( !$ConfigItem->{ConfigItemID} ) {
        return $LayoutObject->ErrorScreen(
            Message => "No config item found for config item id $ConfigItemID and version id $VersionID!",
            Comment => 'Please contact the admin.',
        );
    }

    # check if config item id and version id from request refer to same config item
    if ( $ConfigItem->{ConfigItemID} != $ConfigItemID ) {
        if ( !$ConfigItem->{ConfigItemID} ) {
            return $LayoutObject->ErrorScreen(
                Message => "Invalid request!",
                Comment => 'Please contact the admin.',
            );
        }
    }

    # check for access rights
    my $HasAccess = $ConfigItemObject->Permission(
        Scope  => 'Item',
        ItemID => $ConfigItem->{ConfigItemID},
        UserID => $Self->{UserID},
        Type   => $Self->{Config}{Permission},
    );

    if ( !$HasAccess ) {

        # error page
        return $LayoutObject->ErrorScreen(
            Message => 'Can\'t show config item, no access rights given!',
            Comment => 'Please contact the admin.',
        );
    }

    # prepare PDF
    my %Page = (
        Width           => $Self->{Config}{PageSetting}{PageWidth} / $Self->{mm},     # (optional) default 595 (Din A4) - _ both or nothing
        Height          => $Self->{Config}{PageSetting}{PageHeight} / $Self->{mm},    # (optional) default 842 (Din A4) -
        PageOrientation => $Self->{Config}{PageSetting}{PageOrientation},             # (optional) default normal (normal|landscape)
        MarginTop       => $Self->{Config}{PageSetting}{MarginTop},                   # (optional) default 0 -
        MarginRight     => $Self->{Config}{PageSetting}{MarginRight},                 # (optional) default 0  |_ all or nothing
        MarginBottom    => $Self->{Config}{PageSetting}{MarginBottom},                # (optional) default 0  |
        MarginLeft      => $Self->{Config}{PageSetting}{MarginLeft},                  # (optional) default 0 -
        ShowPageNumber  => 0,                                                         # (optional) default 1
    );

    # create new pdf document
    $PDFObject->DocumentNew(
        Encode => $LayoutObject->{UserCharset},
    );

    # create first pdf page
    $PDFObject->PageBlankNew(
        %Page,
    );

    # output general information
    $Self->_PDFOutputGeneralInfos(
        Page       => \%Page,
        ConfigItem => $ConfigItem,
    );

    my $PDFString = $PDFObject->DocumentOutput();

    # get current timestamp for filename
    my $DateTimeObject = $Kernel::OM->Create('Kernel::System::DateTime');
    if ( $Self->{UserTimeZone} ) {
        $DateTimeObject->ToTimeZone( TimeZone => $Self->{UserTimeZone} );
    }

    # create filename
    my $Filename = 'configitem_' . $ConfigItem->{Number} . '_';
    $Filename .= $DateTimeObject->Format( Format => '%Y-%m-%d_%H:%M' );
    $Filename .= '.pdf';
    my $CleanedFilename = $Kernel::OM->Get('Kernel::System::Main')->FilenameCleanUp(
        Filename => $Filename,
        Type     => 'Attachment',
    );

    my %AttachmentData = (
        Filename    => $CleanedFilename,
        ContentType => 'application/pdf',
        Content     => $PDFString,
        Disposition => 'attachment',
    );

    return $LayoutObject->Attachment(
        %AttachmentData,
    );
}

sub _PDFOutputGeneralInfos {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Page ConfigItem)) {
        if ( !defined $Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $PDFObject    = $Kernel::OM->Get('Kernel::System::PDF');

    # get readable values for config item dynamic fields
    my %ReadableConfigItemData;
    for my $Key ( keys $Param{ConfigItem}->%* ) {

        if ( $Key =~ /^DynamicField_(.+)$/ ) {

            # get field config
            my $FieldName          = $1;
            my $DynamicFieldConfig = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
                Name => $FieldName,
            );

            # fetch and set value
            my $ValueStrg = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->ReadableValueRender(
                DynamicFieldConfig => $DynamicFieldConfig,
                Value              => $Param{ConfigItem}{$Key},
                ValueMaxChars      => 30,
                TitleMaxChars      => 30,
            );
            $ReadableConfigItemData{$Key} = $ValueStrg->{Value};
        }
        else {
            $ReadableConfigItemData{$Key} = $Param{ConfigItem}{$Key};
        }
    }

    # print Logo
    if ( $Self->{Config}{LogoSetting} ) {

        # check if file exists
        my $Home = $Kernel::OM->Get('Kernel::Config')->Get('Home');
        my $Path = "$Home/$Self->{Config}{LogoSetting}{LogoPath}";
        if ( -e $Path ) {

            $PDFObject->PositionSet(
                X => $Self->{Config}{LogoSetting}{ImagePosition_X},
                Y => $Self->{Config}{LogoSetting}{ImagePosition_Y},
            );

            my %Image = (
                File   => $Path,
                Type   => $Self->{Config}{LogoSetting}{DisplayType},
                Width  => $Self->{Config}{LogoSetting}{ImageWidth},
                Height => $Self->{Config}{LogoSetting}{ImageHeight},
            );

            $PDFObject->Image(%Image);
        }
    }

    # print Table
    if ( $Self->{Config}{TableSetting} ) {

        $PDFObject->PositionSet(
            X => $Self->{Config}{TableSetting}{TablePosition_X},
            Y => $Self->{Config}{TableSetting}{TablePosition_Y},
        );

        my %TableParam;

        $TableParam{CellData}[0][0]{Font}     = 'ProportionalBold';
        $TableParam{CellData}[0][0]{FontSize} = $Self->{Config}{TableSetting}{FontSize};
        $TableParam{CellData}[0][0]{Align}    = 'left';
        $TableParam{CellData}[0][0]{Content}  = $ReadableConfigItemData{'Name'};

        $TableParam{CellData}[1][0]{Font}     = 'Proportional';
        $TableParam{CellData}[1][0]{FontSize} = $Self->{Config}{TableSetting}{FontSize};
        $TableParam{CellData}[1][0]{Align}    = 'left';

        # Ensure that each variable is a string and set default to an empty string if not defined or empty
        my $hardware_sn = defined $ReadableConfigItemData{'DynamicField_Hardware-SerialNumber'}
            ? (length($ReadableConfigItemData{'DynamicField_Hardware-SerialNumber'}) > 0
                ? "$ReadableConfigItemData{'DynamicField_Hardware-SerialNumber'}"
                : "")
            : "";

        my $computer_sn = defined $ReadableConfigItemData{'DynamicField_Computer-SerialNumber'}
            ? (length($ReadableConfigItemData{'DynamicField_Computer-SerialNumber'}) > 0
                ? "$ReadableConfigItemData{'DynamicField_Computer-SerialNumber'}"
                : "")
            : "";

        my $software_sn = defined $ReadableConfigItemData{'DynamicField_Software-SerialNumber'}
            ? (length($ReadableConfigItemData{'DynamicField_Software-SerialNumber'}) > 0
                ? "$ReadableConfigItemData{'DynamicField_Software-SerialNumber'}"
                : "")
            : "";

        # If at least one of the Serial Numbers is not empty, set S/N, otherwise empty
        if ($hardware_sn ne '' || $computer_sn ne '' || $software_sn ne '') {
            $TableParam{CellData}[1][0]{Content} = "S/N: $hardware_sn $computer_sn $software_sn";
        } else {
            $TableParam{CellData}[1][0]{Content} = '';
        }

        use strict;
        use warnings;
        use Time::Piece;

        # Function for converting and comparing date values
        sub check_and_format_date {
            my ($date_str) = @_;
            my $formatted_date = '';

            # Check if the date text is defined and not empty
            if (defined $date_str && length($date_str) > 0) {
                eval {
                    my $date = Time::Piece->strptime($date_str, '%Y-%m-%d');
                    my $today = Time::Piece->new;  # aktuelles Datum
                    if ($date < $today) {
                        $formatted_date = '';
                    } else {
                        $formatted_date = $date->strftime('%d.%m.%Y');
                    }
                };
                # Error handling for invalid date formats
                if ($@) {
                    warn "Date parsing error: $@";
                    $formatted_date = '';
                }
            }

            return $formatted_date;
        }

    # Ensure that each variable is a string and set default to an empty string if not defined or empty
	my $hardware_wed = check_and_format_date($ReadableConfigItemData{'DynamicField_Hardware-WarrantyExpirationDate'});
	my $computer_wed = check_and_format_date($ReadableConfigItemData{'DynamicField_Computer-WarrantyExpirationDate'});

	# Wenn mindestens einer der beiden Werte nicht leer ist, setze WED
	if ($hardware_wed ne '' || $computer_wed ne '') {
		$TableParam{CellData}[2][0]{Font}     = 'Proportional';
		$TableParam{CellData}[2][0]{FontSize} = $Self->{Config}{TableSetting}{FontSize};
		$TableParam{CellData}[2][0]{Align}    = 'left';
		$TableParam{CellData}[2][0]{Content}  = "WED: $hardware_wed $computer_wed";
	}

        $TableParam{ColumnData}[0]{Width} = $Self->{Config}{TableSetting}{ValueWidth};
        $TableParam{Type}                 = $Self->{Config}{TableSetting}{Type};
        $TableParam{Border}               = $Self->{Config}{TableSetting}{Border};
        $TableParam{FontSize}             = $Self->{Config}{TableSetting}{FontSize};
        $TableParam{Padding}              = $Self->{Config}{TableSetting}{Padding};
        $TableParam{PaddingTop}           = $Self->{Config}{TableSetting}{PaddingTop};
        $TableParam{PaddingBottom}        = $Self->{Config}{TableSetting}{PaddingBottom};
        $TableParam{PaddingLeft}          = $Self->{Config}{TableSetting}{PaddingLeft};
        $TableParam{PaddingRight}         = $Self->{Config}{TableSetting}{PaddingRight};

        # output table (or a fragment of it)
        %TableParam = $PDFObject->Table(%TableParam);
    }


    # Set window preferences
    $PDFObject->PositionSet(
        X => "left",
        Y => "top",
    );

    # print Barcode
    if ( $Self->{Config}{BarcodeSetting} ) {

        my $Data = $Param{ConfigItem}{ $Self->{Config}{BarcodeSetting}{BarcodeField} };

        # create link in case of QR code
        if ( $Self->{Config}{BarcodeSetting}{Code} eq 'qr' ) {

            if ( $Self->{Config}{BarcodeSetting}{QRCodeLink} =~ /ITSMConfigItemZoom$/ ) {

                # get link parts
                my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
                my $HTTPType     = $ConfigObject->Get('HttpType');
                my $FQDN         = $ConfigObject->Get('FQDN');

                $Data = "$HTTPType://$FQDN/otobo/index.pl?Action=$Self->{Config}{BarcodeSetting}{QRCodeLink};ConfigItemID=$Param{ConfigItem}{ConfigItemID}";
            }
            elsif ( $Self->{Config}{BarcodeSetting}{QRCodeLink} eq 'Custom' ) {
                $Data = $Kernel::OM->Get('Kernel::Output::HTML::Layout')->Output(
                    Template => $Self->{Config}{BarcodeSetting}{CustomLink},
                    Data     => $Param{ConfigItem},
                );
            }
        }

        my %Options = (
            'bar_height'   => $Self->{Config}{BarcodeSetting}{Zone}             || 10,
            'bar_extend'   => $Self->{Config}{BarcodeSetting}{LowerMendingZone} || 15,
            'font'         => $Self->{Config}{BarcodeSetting}{Font} ? $PDFObject->{PDF}->font( $Self->{Config}{BarcodeSetting}{Font} ) : undef,
            'font_size'    => $Self->{Config}{BarcodeSetting}{FontSize}    || 8,
            'bar_overflow' => $Self->{Config}{BarcodeSetting}{BarOverflow} || 0.5,
        );

        # be cautious and set caption only if wanted, because PDF::API2 checks with 'exists' at one point
        if ( $Self->{Config}{BarcodeSetting}{Caption} ) {
            $Options{caption} = $Param{ConfigItem}{ $Self->{Config}{BarcodeSetting}{BarcodeField} };
        }
        else {
            delete $Options{caption};
        }

        # add barcode
        my $Code = $PDFObject->{PDF}
            ->barcode(
                $Self->{Config}{BarcodeSetting}{Code},
                $Data,
                %Options,
            );

        $PDFObject->{PDF}->open_page(1)->object(
            $Code,
            $Self->{Config}{BarcodeSetting}{BarcodePosition_X},
            $Self->{Config}{BarcodeSetting}{BarcodePosition_Y},
            $Self->{Config}{BarcodeSetting}{Scale_X},
            $Self->{Config}{BarcodeSetting}{Scale_Y},
        );
    }

    # print Footer
    if ( $Self->{Config}{FooterSetting} ) {

        $PDFObject->PositionSet(
            X => $Self->{Config}{FooterSetting}{FooterPosition_X},
            Y => $Self->{Config}{FooterSetting}{FooterPosition_Y},
        );

        # evaluate FooterText
        my $FooterText = $LayoutObject->Output(
            Template => $Self->{Config}{FooterSetting}{FooterText},
            Data     => \%ReadableConfigItemData,
        );

        $PDFObject->Text(
            Text     => $FooterText,
            Font     => $Self->{Config}->{FooterSetting}->{Font},
            FontSize => $Self->{Config}->{FooterSetting}->{FontSize},
            Color    => $Self->{Config}->{FooterSetting}->{Color},
            Align    => $Self->{Config}->{FooterSetting}->{Align},
            Lead     => $Self->{Config}->{FooterSetting}->{Lead},
        );
    }

    return 1;
}

1;
