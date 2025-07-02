"""Database connection and session management."""
import structlog
from contextlib import contextmanager
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import QueuePool
from .config import config
from .models import Base

logger = structlog.get_logger(__name__)


class DatabaseManager:
    """Database manager for handling connections and sessions."""
    
    def __init__(self):
        self.engine = None
        self.SessionLocal = None
        self._initialized = False
    
    def initialize(self):
        """Initialize the database connection."""
        if self._initialized:
            return
        
        logger.info("Initializing database connection", database_url=config.database_url)
        
        # Create engine with connection pooling
        self.engine = create_engine(
            config.database_url,
            poolclass=QueuePool,
            pool_size=20,
            max_overflow=30,
            pool_pre_ping=True,
            pool_recycle=3600,
            echo=config.log_level == "DEBUG"
        )
        
        # Create session factory
        self.SessionLocal = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine
        )
        
        self._initialized = True
        logger.info("Database connection initialized successfully")
    
    def create_tables(self):
        """Create all database tables."""
        if not self._initialized:
            self.initialize()
        
        logger.info("Creating database tables")
        Base.metadata.create_all(bind=self.engine)
        logger.info("Database tables created successfully")
    
    @contextmanager
    def get_session(self) -> Session:
        """Get a database session with automatic cleanup."""
        if not self._initialized:
            self.initialize()
        
        session = self.SessionLocal()
        try:
            yield session
            session.commit()
        except Exception as e:
            session.rollback()
            logger.error("Database session error", error=str(e))
            raise
        finally:
            session.close()
    
    def get_session_sync(self) -> Session:
        """Get a synchronous database session."""
        if not self._initialized:
            self.initialize()
        
        return self.SessionLocal()
    
    def close(self):
        """Close database connections."""
        if self.engine:
            self.engine.dispose()
            logger.info("Database connections closed")


# Global database manager instance
db_manager = DatabaseManager()