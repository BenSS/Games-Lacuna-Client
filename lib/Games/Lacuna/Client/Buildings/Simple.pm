package Games::Lacuna::Client::Buildings::Simple;
use 5.0080000;
use strict;
use warnings;
use Carp 'croak';

use Games::Lacuna::Client;
use Games::Lacuna::Client::Module;
use Class::MOP;

our @BuildingTypes = (qw(
    Algae
    AlgaePond
    Apple
    Bean
    Beeldeban
    BeeldebanNest
    Bread
    Burger
    Capitol
    Cheese
    Chip
    Cider
    CitadelOfKnope
    CloakingLab
    Corn
    CornMeal
    Crater
    CrashedShipSite
    Dairy
    Denton
    Espionage
    EssentiaVein
    Fission
    Fusion
    GasGiantLab
    GasGiantPlatform
    GeneticsLab
    Geo
    GeoThermalVent
    Grove
    HydroCarbon
    InterDimensionalRift
    KalavianRuins
    Lake
    Lagoon
    Lapis
    LapisForest
    LibraryOfJith
    LuxuryHousing
    Malcud
    MalcudField
    MassadsHenge
    Mine
    MunitionsLab
    NaturalSpring
    OracleOfAnid
    OreRefinery
    Oversight
    Pancake
    PantheonOfHagness
    Pie
    PilotTraining
    Potato
    Propulsion
    Ravine
    RockyOutcrop
    Sand
    Shake
    Singularity
    Soup
    Stockpile
    SubspaceSupplyDepot
    Syrup
    TempleOfTheDrajilites
    TerraformingLab
    TerraformingPlatform
    ThemePark
    University
    Volcano
    WasteEnergy
    WasteSequestration
    WasteDigester
    WasteTreatment
    WaterProduction
    WaterPurification
    WaterReclamation
    Wheat
  ),
);


#  WasteDigester => url is 'wastetreatment' according to docs, but I don't believe it!

sub init {
  my $class = shift;
  foreach my $type (@BuildingTypes) {
    my $class_name = "Games::Lacuna::Client::Buildings::$type";
    Class::MOP::Class->create(
      $class_name => (
        superclasses => ['Games::Lacuna::Client::Buildings'],
      )
    );
  }
}

__PACKAGE__->init();

1;
__END__

=head1 NAME

Games::Lacuna::Client::Buildings::Simple - All the simple buildings

=head1 SYNOPSIS

  use Games::Lacuna::Client;

=head1 DESCRIPTION

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
