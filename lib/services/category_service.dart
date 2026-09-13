class CategoryService {
  static const Map<String, List<String>> categoryKeywords = {
    'Science': [
      'science', 'biology', 'chemistry', 'physics', 'lab', 'experiment',
      'genetics', 'ecology', 'astronomy', 'geology', 'molecule', 'cell',
      'dna', 'evolution', 'climate', 'ecosystem', 'biodiversity', 'scientific',
      'research', 'study', 'analysis', 'microscope', 'disease', 'virus',
      'bacteria', 'organism', 'specimen', 'laboratory', 'scientist'
    ],
    'Programming': [
      'programming', 'code', 'java', 'python', 'flutter', 'dart', 'android',
      'ios', 'swift', 'kotlin', 'javascript', 'react', 'angular', 'vue',
      'web', 'api', 'database', 'sql', 'algorithm', 'data structure',
      'machine learning', 'ai', 'artificial intelligence', 'computer science',
      'software', 'developer', 'coding', 'script', 'cyber', 'backend',
      'frontend', 'devops', 'cloud', 'github', 'open source', 'app'
    ],
    'Business': [
      'business', 'market', 'finance', 'account', 'economics', 'management',
      'startup', 'invest', 'budget', 'sales', 'marketing', 'strategy',
      'entrepreneur', 'commerce', 'trade', 'stock', 'bank', 'insurance',
      'leadership', 'analytics', 'consumer', 'supply chain', 'logistics'
    ],
    'History': [
      'history', 'ancient', 'war', 'civilization', 'medieval', 'empire',
      'revolution', 'colony', 'kingdom', 'dynasty', 'world war', 'cold war',
      'renaissance', 'enlightenment', 'industrial', 'historical', 'archaeology',
      'artifacts', 'timeline', 'century', 'colonial', 'independence'
    ],
    'Mathematics': [
      'math', 'algebra', 'geometry', 'calculus', 'statistics', 'trigonometry',
      'probability', 'linear', 'matrix', 'differential', 'integral',
      'arithmetic', 'number theory', 'topology', 'analysis', 'theorem',
      'equation', 'function', 'graph', 'variable', 'vector'
    ],
    'Literature': [
      'literature', 'poem', 'novel', 'story', 'fiction', 'drama', 'prose',
      'poetry', 'author', 'writer', 'book', 'chapter', 'verse', 'grammar',
      'linguistics', 'language', 'essay', 'literary', 'narrative', 'critique',
      'biography', 'autobiography', 'fiction', 'genre'
    ],
    'Art & Design': [
      'art', 'painting', 'drawing', 'sculpture', 'design', 'architecture',
      'photography', 'museum', 'gallery', 'artist', 'visual', 'creative',
      'craft', 'illustration', 'logo', 'graphic', 'typography', 'aesthetic',
      'composition', 'color theory', 'canvas', 'sketch'
    ],
    'Health & Medicine': [
      'health', 'medicine', 'doctor', 'nurse', 'hospital', 'disease',
      'surgery', 'pharma', 'drug', 'therapy', 'nutrition', 'fitness',
      'medical', 'clinical', 'patient', 'diagnosis', 'treatment', 'wellness',
      'mental health', 'physical', 'exercise', 'anatomy', 'physiology'
    ],
    'Education': [
      'education', 'school', 'college', 'university', 'teacher', 'student',
      'exam', 'lesson', 'curriculum', 'degree', 'pedagogy', 'learning',
      'classroom', 'lecture', 'assignment', 'homework', 'quiz', 'pedagogy',
      'teaching', 'educational', 'scholar', 'academic'
    ],
    'Social Sciences': [
      'sociology', 'psychology', 'anthropology', 'philosophy', 'politics',
      'law', 'legal', 'social', 'ethics', 'culture', 'religion', 'society',
      'government', 'policy', 'democracy', 'human rights', 'gender', 'identity',
      'community', 'justice', 'ideology'
    ],
    'Engineering': [
      'engineering', 'mechanical', 'electrical', 'civil', 'chemical',
      'robotics', 'automation', 'thermal', 'structural', 'aerospace',
      'electronics', 'circuit', 'motor', 'machine', 'manufacturing', 'design',
      'systems', 'control', 'thermodynamics', 'materials'
    ],
    'Personal': [
      'resume', 'cv', 'cover', 'letter', 'personal', 'bio', 'profile',
      'portfolio', 'application', 'job', 'career', 'experience', 'references'
    ],
    'Summary': [
      'summary', 'overview', 'synopsis'
    ],
  };

  static Map<String, int> getCategoryScores(String text, {Map<String, List<String>>? customCategories}) {
    // Limit text length for efficiency, categorization doesn't need the whole book
    final String sampleText = text.length > 10000 ? text.substring(0, 10000) : text;
    final lower = sampleText.toLowerCase();
    final scores = <String, int>{};
    
    // Use a tokenized approach to avoid false positives and speed up matching
    final words = lower.split(RegExp(r'\s+')).toSet();
    
    // Check custom categories first
    if (customCategories != null) {
      for (var entry in customCategories.entries) {
        int count = 0;
        for (var keyword in entry.value) {
          if (words.contains(keyword) || lower.contains(keyword)) count++;
        }
        if (count > 0) scores[entry.key] = count;
      }
    }
    
    // Then check defaults
    for (var entry in categoryKeywords.entries) {
      int count = 0;
      for (var keyword in entry.value) {
        if (words.contains(keyword) || (keyword.contains(' ') && lower.contains(keyword))) count++;
      }
      if (count > 0) scores[entry.key] = count;
    }
    return scores;
  }

  static String getBestCategory(String text, {int threshold = 2, Map<String, List<String>>? customCategories}) {
    final scores = getCategoryScores(text, customCategories: customCategories);
    if (scores.isEmpty) return 'General';
    final best = scores.entries.reduce((a, b) => a.value > b.value ? a : b);
    if (best.value >= threshold) {
      return best.key;
    } else {
      return 'General';
    }
  }
}