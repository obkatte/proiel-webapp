#--
#
# Copyright 2007, 2008, 2009, 2010, 2011, 2012, 2013 University of Oslo
# Copyright 2007, 2008, 2009, 2010, 2011, 2012, 2013 Marius L. Jøhndal
# Copyright 2011 Dag Haug
#
# This file is part of the PROIEL web application.
#
# The PROIEL web application is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.
#
# The PROIEL web application is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with the PROIEL web application.  If not, see
# <http://www.gnu.org/licenses/>.
#
#++

require 'differ'

class SourceDivision < ActiveRecord::Base
  attr_accessible :source_id, :position, :title, :abbreviated_title, :aligned_source_division_id, :presentation_before, :presentation_after
  change_logging

  belongs_to :source
  has_many :sentences
  has_many :tokens, :through => :sentences, :order => 'sentences.sentence_number ASC, token_number ASC'
  belongs_to :aligned_source_division, :class_name => "SourceDivision"

  # Returns the previous source division in a source.
  def previous
    source.source_divisions.where("position < ?", position).order("position DESC").first
  end

  # Returns the next source division in a source.
  def next
    source.source_divisions.where("position > ?", position).order("position ASC").first
  end

  include Ordering

  def ordering_attribute
    :position
  end

  def ordering_collection
    source.source_divisions
  end

  # Returns the parent object for the source division, which will be its
  # source.
  def parent
    source
  end

  # Returns a citation for the source division.
  def citation
    if sentences.empty?
      source.citation_part
    else
      [source.citation_part,
        citation_make_range(sentences.first.tokens.first.citation_part,
                            sentences.last.tokens.last.citation_part)].join(' ')
    end
  end

  # Returns sentence alignments for the source division.
  #
  # ==== Options
  # <tt>:automatic</tt> -- If true, will automatically align sentences
  # whose sentence alignment has not been set.
  def sentence_alignments(options = {})
    if aligned_source_division
      base_sentences = sentences
      aligned_sentences = aligned_source_division.sentences

      align_sentences(aligned_sentences, base_sentences, options[:automatic])
    else
      []
    end
  end

  # Language tag for the source division
  delegate :language_tag, :to => :source

  # Language for the source division
  delegate :language, :to => :source

  protected

  def self.search(query, options = {})
    options[:conditions] ||= query.inject([nil,[]]) do |m,v|
      [[m.first, (case v[0]
                 when :source_id
                   'source_id = ?'
                 when :title
                   'title LIKE ?'
                 else
                   raise "Unknown key #{v[0]}"
                  end)].compact.join(" AND "),
       m.last + [(v[1].to_i.to_s == v[1] ? v[1].to_i : "%#{v[1]}%" )]
      ]
    end.flatten unless query.empty?

    paginate options
  end

  public

  # Returns a collection of source divisions that are candidates for
  # alignment with this source division.
  def alignment_candidates
    SourceDivision.find(:all, :conditions => ["source_id != ?", self.source.id])
  end

  def visualize_semantic_relation(srt)
    result = nil
    errors = nil

    Open3.popen3("dot -Tsvg") do |dot, img, err|
      dot.write semantic_relation_dot(srt)
      dot.close
      result = img.read
      errors = err.read
    end

    raise VisualizationError, "graphviz exited: #{errors}" unless errors.blank?

    result
  end

  private

  def semantic_relation_heads(srt)
    tokens.select do |t|
     t.outgoing_semantic_relations.any? { |osa| osa.semantic_relation_type == srt} or t.incoming_semantic_relations.any? { |isa| isa.semantic_relation_type == srt }
    end.uniq
  end

  def semantic_relation_dot(srt)
    srh = semantic_relation_heads(srt)
    "digraph discourse {\n" +
     "\trankdir=TD;\n" +
      "\tnode [shape = ellipse];\n" +
      (srh.map do |head|
         l = "\t#{head.id} [label = " + '"' + head.label_semantic_relation_span(srt) + '"];' + "\n" +
           "\tH#{head.id} [label = " + '"", shape=none];' + "\n" +
           "\t#{head.id} -> H#{head.id} [style=invis];"
         if head.outgoing_semantic_relations.empty? and head.find_semantic_relation_head(srt)
           l += "\n\t#{head.find_semantic_relation_head(srt).id} -> #{head.id} [label = " + '"CONTAINS", style=dashed];'
         end
         l += (head.outgoing_semantic_relations.map do |sr|
                 "\t#{sr.target.id} -> #{sr.controller.id} [ label = " + '"' + sr.semantic_relation_tag.tag + '"];'
                 end.join("\n"))
         l
       end.join("\n")) +
      "\n}"
  end

  public

  def has_discourse_annotation?
    tokens.any? do |t|
      t.has_relation_type?(SemanticRelationType.find_by_tag('Discourse'))
    end
  end

  # Tests if review is complete.
  def review_complete?
    not sentences.where('reviewed_by IS NULL').exists?
  end

  # Tests if annotation is complete.
  def annotation_complete?
    not sentences.where('annotated_by IS NULL').exists?
  end

  # Returns the completion state.
  def completion
    if annotation_complete?
      if review_complete?
        :reviewed
      else
        :annotated
      end
    else
      :unannotated
    end
  end

  # Returns all contrast groups defined in the source division.
  def contrast_groups
    tokens.where('contrast_group IS NOT NULL').uniq.pluck(:contrast_group)
  end

  # Delete contrast group from source division.
  def delete_contrast_group!(contrast_number)
    contrast_number = contrast_number.to_i
    raise 'Invalid contrast number' unless contrast_number > 0

    tokens.where('contrast_group LIKE ?', "#{contrast_number}%").update_all :contrast_group => nil
  end
end
