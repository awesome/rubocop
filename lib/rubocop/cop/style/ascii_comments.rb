# encoding: utf-8

module Rubocop
  module Cop
    module Style
      # This cop checks for non-ascii (non-English) characters
      # in comments.
      class AsciiComments < Cop
        MSG = 'Use only ascii symbols in comments.'

        def investigate(processed_source)
          processed_source.comments.each do |comment|
            if comment.text =~ /[^\x00-\x7f]/
              add_offence(:convention, comment.loc.expression, MSG)
            end
          end
        end
      end
    end
  end
end
