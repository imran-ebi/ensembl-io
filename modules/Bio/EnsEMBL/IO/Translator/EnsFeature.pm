=head1 LICENSE

Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

Bio::EnsEMBL::IO::Translator::EnsFeature - Translator for Ensembl Features (Gene, Transcript, Exon, Translation)

=head1 SYNOPSIS

  use Bio::EnsEMBL::IO::Translator::EnsFeature;

  my $translator = Bio::EnsEMBL::IO::translator::EnsFeature->new();

  my @values = $translator->batch_fields($object, @fields);

  my $seqname = $translator->seqname($object);

=head1 Description

Translator to interrogate Ensembl base features for attributes needed by writers. For each attribute type

=cut

package Bio::EnsEMBL::IO::Translator::EnsFeature;


use base qw/Bio::EnsEMBL::IO::Translator/;


use strict;
use warnings;
use Carp;
use URI::Escape;
use Bio::EnsEMBL::Utils::SequenceOntologyMapper;
use Bio::EnsEMBL::Utils::Exception qw/throw/;

my %ens_field_callbacks = (seqname => '$self->can(\'seqname\')',
                           source  => '$self->can(\'source\')',
                           type  => '$self->can(\'type\')',
                           start  => '$self->can(\'start\')',
                           end  => '$self->can(\'end\')',
                           score  => '$self->can(\'score\')',
                           strand  => '$self->can(\'strand\')',
                           phase  => '$self->can(\'phase\')',
                           attributes  => '$self->can(\'attributes\')'
                           );

=head2 new

    Returntype   : Bio::EnsEMBL::IO::Translator::EnsFeature

=cut

sub new {
    my ($class) = @_;
  
    my $self = $class->SUPER::new();

    # Once we have the instance, add our customized callbacks
    # to the translator
    $self->add_callbacks(\%ens_field_callbacks);

    $self->{default_source} = '.';
    my $oa = Bio::EnsEMBL::Registry->get_adaptor('multi', 'ontology', 'OntologyTerm');
    $self->{'mapper'} = Bio::EnsEMBL::Utils::SequenceOntologyMapper->new($oa);

    return $self;

}

sub seqname {
    my $self = shift;
    my $object = shift;

    return $object->seq_region_name() ? $object->seq_region_name() : '?';
}

sub source {
    my $self = shift;
    my $object = shift;

    my $source;
    if( ref($object)->isa('Bio::EnsEMBL::Slice') ) {
	$source = $object->source || $object->coord_system->version
    } elsif( ref($object)->isa('Bio::EnsEMBL::Gene') ||
	ref($object)->isa('Bio::EnsEMBL::Transcript') ||
	ref($object)->isa('Bio::EnsEMBL::PredictionTranscript') ) {
	$source = $object->source();
    } elsif( ref($object)->isa('Bio::EnsEMBL::ExonTranscript') ||
	     ref($object)->isa('Bio::EnsEMBL::CDS') ||
	     ref($object)->isa('Bio::EnsEMBL::UTR') ) {
	$source = $object->transcript()->source();
    }

    if( ! defined $source ) {
	if ( ref($object)->isa('Bio::EnsEMBL::Feature') &&
	     defined($object->analysis) && $object->analysis->gff_source() ) {
	    $source = $object->analysis->gff_source();
	} else {
	    $source = '.';
	}
    }

    return $source;
}

sub type {
    my $self = shift;
    my $object = shift;

    return $self->so_term($object);

}

sub start {
    my $self = shift;
    my $object = shift;

    return $object->start();
}

sub end {
    my $self = shift;
    my $object = shift;

    my $end = $object->end();

    # the start coordinate of the feature, here shifted to chromosomal coordinates
    # Start and end must be in ascending order for GXF. Circular genomes require the length of 
    # the circuit to be added on.    
    if( $object->start() > $object->end() ) {
	if ($object->slice() && $object->slice()->is_circular() ) {
	    $end = $end + $object->seq_region_length;
	}
	# non-circular, but end still before start
	else {
	    $end = $object->start();
	}
    }

    return $end;
}

sub score {
    my $self = shift;
    my $object = shift;

    # score, for variations only. We may need some isa() later
    return '.';
}

sub strand {
    my $self = shift;
    my $object = shift;

    if( ref($object)->isa('Bio::EnsEMBL::Slice') ) {
	return '.';
    } else {
	return ( $self->{_strand_conversion}->{ $object->{strand} } ? $self->{_strand_conversion}->{ $object->strand() } : $object->strand() );
    }
}

sub phase {
    my $self = shift;
    my $object = shift;

    if (ref($object)->isa('Bio::EnsEMBL::CDS') ) {
	return $object->phase();
    } else {
	return '.';
    }
}

sub attributes {
    my $self = shift;
    my $object = shift;

    # Oh this is a mess... hopefully we can refactor and find a better way
    my %summary = %{$object->summary_as_hash};
    delete $summary{'seq_region_start'};
    delete $summary{'seq_region_name'};
    delete $summary{'start'};
    delete $summary{'end'};
    delete $summary{'strand'};
    delete $summary{'phase'};
    delete $summary{'score'};
    delete $summary{'source'};
    delete $summary{'type'};

#    my @attrs;
    my %attrs;
    my @ordered_keys = grep { exists $summary{$_} } qw(id Name Alias Parent Target Gap Derives_from Note Dbxref Ontology_term Is_circular);
    my @ordered_values = @summary{@ordered_keys};
    while (my $key = shift @ordered_keys) {
	my $value = shift @ordered_values;
	delete $summary{$key};
	if ($value && $value ne '') {
	    if ($key =~ /id/) {
                $key = uc($key);
		if ($object->isa('Bio::EnsEMBL::Transcript')) {
                    $value = 'transcript:' . $value;
		} elsif ($object->isa('Bio::EnsEMBL::Gene')) {
                    $value = 'gene:' . $value;
		} elsif ($object->isa('Bio::EnsEMBL::Exon')) {
                    $key = 'Name';
		} elsif ($object->isa('Bio::EnsEMBL::CDS')) {
                    my $trans_spliced = $object->transcript->get_all_Attributes('trans_spliced');
                    if (scalar(@$trans_spliced)) {
			$value = $self->so_term($object) . ':' . join('_', $value, $object->seq_region_name, $object->seq_region_strand);
                    } else {
			$value = $self->so_term($object) . ':' . $value;
                    }
		} else {
                    $value = $self->so_term($object) . ':' . $value;
		}
	    }

	    if ($key eq 'Parent') {
		if ($object->isa('Bio::EnsEMBL::Transcript')) {
                    $value = 'gene:' . $value;
		} elsif ($object->isa('Bio::EnsEMBL::Exon') || $object->isa('Bio::EnsEMBL::UTR') || $object->isa('Bio::EnsEMBL::CDS')) {
                    $value = 'transcript:' . $value;
		}
	    }

	    if (ref $value eq "ARRAY" && scalar(@{$value}) > 0) {
		$attrs{$key} = join (',',map { uri_escape($_,'\t\n\r;=%&,') } grep { defined $_ } @{$value});
	    } else {
		$attrs{$key} = uri_escape($value,'\t\n\r;=%&,');
	    }
	}
    }

    #   Catch the remaining keys, containing whatever else the Feature provided
    my @keys = sort keys %summary;
    while(my $attribute = shift @keys) {

	if (ref $summary{$attribute} eq "ARRAY") {
	    if (scalar(@{$summary{$attribute}}) > 0) {
		$attrs{$attribute} = join (',',map { uri_escape($_,'\t\n\r;=%&,') } grep { defined $_ } @{$summary{$attribute}});
	    }
	} else {
	    if (defined $summary{$attribute}) { 
		$attrs{$attribute} = uri_escape($summary{$attribute},'\t\n\r;=%&,'); 
	    }
	}
    }

    return \%attrs;
}

sub gtf_attributes {
    my $self = shift;
    my $object = shift;

    my %attrs;
    
}

=head2 so_term

    Description: Accessor to look up the Ontology term for an object
    Args[1]    : Feature to loop up term for
    Returntype : String (term)
    Exceptions : If the term can't be found by the Ontology adaptor

=cut

sub so_term {
    my $self = shift;
    my $object = shift;
    
    my $so_term = eval { $self->{'mapper'}->to_name($object); };
    if($@) {
	throw sprintf "Unable to map feature %s to SO term.\n$@", $object->display_id;
    }

    if ($so_term eq 'protein_coding_gene') { 
    # Special treatment for protein_coding_gene, as more commonly expected term is 'gene'
	$so_term = 'gene';
    }

    return $so_term;
}

=head2 _default_score

    Description: Return the default source type for a feature
    Returntype : String

=cut

sub _default_source {
    my ($self) = @_;
    return $self->{default_source};
}

=head2 strand_conversion

    Description: Sets hash giving the strand conversion for this
                 output type
    Args[1]    : Reference to hash

=cut

sub strand_conversion {
    my $self = shift;

    if( @_ ) {
	$self->{_strand_conversion} = shift;
    }

    return $self->{_strand_conversion};
}