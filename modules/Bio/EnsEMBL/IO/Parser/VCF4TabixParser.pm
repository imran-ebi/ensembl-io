=pod

=head1 LICENSE

  Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 NAME

Bio::EnsEMBL::IO::Parser::VCF4TabixParser - A line-based parser devoted to VCF format version 4.2, using the tabix index tool

=cut

=head1 DESCRIPTION

The Variant Call Format (VCF) specification for the version 4.2 is available at the following address:
http://samtools.github.io/hts-specs/VCFv4.2.pdfs
The tabix tool is available at the following address:
https://github.com/samtools/tabix

=cut

package Bio::EnsEMBL::IO::Parser::VCF4TabixParser;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw(warning);
use Bio::EnsEMBL::IO::TabixParser;
use Bio::EnsEMBL::IO::Parser::BaseVCF4Parser;

use base qw/Bio::EnsEMBL::IO::TabixParser Bio::EnsEMBL::IO::Parser::BaseVCF4Parser/;

sub open {
  my ($caller, $filename, $other_args) = @_;
  my $class = ref($caller) || $caller;
  
  my $delimiter = "\t";   
  my $self = $class->SUPER::open($filename,$other_args);
  
  my $tabix_data = `tabix -H $filename`;
  foreach my $line (split("\n",$tabix_data)) {
    $self->Bio::EnsEMBL::IO::Parser::BaseVCF4Parser::read_metadata($line);
  }
  
  $self->{'delimiter'} = $delimiter;
  return $self;
}


=head2 read_record
    Description: Splits the current block along predefined delimiters
    Returntype : Void 
=cut

sub read_record {
    my $self = shift;
    $self->Bio::EnsEMBL::IO::Parser::BaseVCF4Parser::read_record(@_);
}

1;
